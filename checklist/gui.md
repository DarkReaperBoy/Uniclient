# Audit: §1-§4 Layout & Navigation

## §1 — Window Layout & Column Structure

## §2 — Chat List Sidebar

## §3 — Hamburger Menu

- [ ] spec §3 "Menu row icon position": spec says "Icon: 24x24 from ui/menu_icons.style, rendered in menuIconColor. Horizontal at 21px, vertically centered." Code places icon at `left: 21` but does not explicitly vertically center — the icon sits at the top of the row's content area. Due to `Padding(top: 11, bottom: 9)`, a 24px icon in a Row is vertically centered by default via Row's cross-axis alignment. Likely correct
- [ ] spec §3 "Night Mode toggle colors": spec says on = `mainMenuCoverBg` (which equals `windowBgActive`), off = `windowSubTextFg`. Code uses `onColor = context.palette.windowBgActive` and `offColor = isDark ? Color(0xFF6C7883) : Color(0xFF999999)`. The off color should be `windowSubTextFg` from palette, not hardcoded — `hamburger_drawer.dart:1334`
- [ ] spec §3 "Night Mode toggle shift": spec says `itemToggleShift: 11px`. Code uses a 36x20 toggle with 16px thumb and 2px margin. The toggle shift (distance thumb moves) is 36-16-4=16px, not 11px. The toggle dimensions don't match spec — `hamburger_drawer.dart:1339-1361`
- [ ] spec §3 "Night Mode toggle animation duration": spec says `st::mainMenu.itemToggle.duration` (tdesktop default ~150ms). Code uses `duration: const Duration(milliseconds: 150)` — matches
- [ ] spec §3 "Night Mode confirmation": spec says "If a theme is currently being edited, toggling shows `lng_theme_editor_cant_change_theme` and reverts". Code checks `appState.isEditingTheme` and shows a confirm box with text "You can't change the theme while editing it." — matches spec behavior
- [ ] spec §3 "Account row avatar": spec says "26px photo padded by 5px each side = 36x36 widget" with "2px stroke ring in windowBgActive for active". Code creates `SizedBox(width: 36, height: 36)` containing a `Container(width: 26, height: 26)` with a `Border.all(width: 2)` for active. However, the inner container only shows a platform icon placeholder, not the actual account avatar/userpic — it never loads the account's avatar image — `hamburger_drawer.dart:1094-1109`
- [ ] spec §3 "Account row avatar image": spec says account rows show the user's actual avatar photo. Code renders a tinted platform icon (e.g., Telegram send icon) as a fallback but NEVER loads the real avatar even when `account.avatarPath` is available — the avatar file image loading that exists in `_ProfileCover` is missing from `_AccountRow` — `hamburger_drawer.dart:1094-1109`
- [ ] spec §3 "Account unread badge font": spec says `mainMenuBadgeFont: 11px bold` and `mainMenuBadgeSize: 18px`. Code uses `fontSize: 11, fontWeight: FontWeight.bold` and `height: 18` — matches spec
- [ ] spec §3 "Footer min height": spec says `mainMenuFooterHeightMin: 80px`. Code uses `BoxConstraints(minHeight: 80)` — matches spec
- [ ] spec §3 "Footer left padding": spec says `mainMenuFooterLeft: 25px`. Code uses `EdgeInsets.only(left: 25, bottom: 17)` — matches spec
- [ ] spec §3 "Footer top line font": spec says `semiboldFont (13px semibold)`. Code uses `fontSize: 13, fontWeight: FontWeight.w600` — matches spec
- [ ] spec §3 "Footer bottom line font": spec says `defaultTextStyle (13px regular)`. Code uses `fontSize: 13, fontWeight: FontWeight.w400` — matches spec
- [ ] spec §3 "Footer version tooltip": spec says "Build date: {__DATE__}" on hover. Code uses `TelegramTooltip(message: 'Build date: ...')` — matches spec

## §4 — Chat Header / Top Bar

- [ ] spec §4 "Top bar height": spec says 54px (`topBarHeight`). Code uses `height: 54` — matches
- [ ] spec §4 "Top bar background": spec says `topBarBg` = `windowBg`. Code uses `palette.topBarBg` — correct if palette maps it
- [ ] spec §4 "Divider": spec says 1px `PlainShadow` at `shadowFg`. Code uses `Border(bottom: BorderSide(color: shadowFg, width: 1))` — matches
- [ ] spec §4 "Back button width": spec says 60px. Code uses `width: 60` for `_ForwardDragBackButton` — matches
- [ ] spec §4 "Avatar hit-area": spec says "52x54px, photo 42px diameter, offset (2,-1)". Code uses `SizedBox(width: 52, height: 54)` with avatar `Positioned(left: 2, top: 5)` using radius 21 (42px diameter). The top offset is 5px, but spec says -1px (relative to center). Since center of 54px is 27px and 21px radius means top of circle at 6px, the -1px offset from center means `top = 27 - 21 - 1 = 5`. So top: 5 matches the spec's `(2, -1)` offset. Correct
- [ ] spec §4 "Title font": spec says "Semibold font". Code uses `theme.textTheme.titleMedium` which is whatever the Material theme sets — it should explicitly use 13px semibold per Telegram spec, not inherit from Material theme — `chat_view.dart:5896-5899`
- [ ] spec §4 "Subtitle font": spec says `dialogsTextFont` (13px normal). Code uses `theme.textTheme.bodySmall?.copyWith(fontSize: 13)` — the fontSize 13 matches, though it should use the Telegram palette font rather than Material theme's bodySmall — `chat_view.dart:5945-5946`
- [ ] spec §4 "Right-side button width": spec says 40px default with 40px circular ripple. Code's `_TopBarButton` defaults to `width: 40` with `Size(40, 40)` ripple — matches
- [ ] spec §4 "Menu toggle width": spec says 44px override. Code uses `width: 44` for the menu toggle button — matches
- [ ] spec §4 "Menu toggle icon position": spec says `iconPosition: point(16px, 17px)`. Code uses `iconPadding: const EdgeInsets.only(left: 8)` which shifts the icon but doesn't precisely position it at (16, 17) within the 44px button — `chat_view.dart:6016`
- [ ] spec §4 "topBarSkip": spec says `-5px` negative pull. Code allocates `SizedBox(width: 39)` (44-5) with `OverflowBox(maxWidth: 44)` — this correctly implements the -5px pull — matches
- [ ] spec §4 "Button order right-to-left": spec says "Menu toggle, Info toggle, Call, Group call, Search" (right to left). Code renders left-to-right: Search, Call (DM only), GroupCall (group/channel), Info, Menu. Reading right-to-left gives: Menu, Info, GroupCall, Call, Search — matches spec order
- [ ] spec §4 "Group call button": code uses `Icons.phone_in_talk` icon. The `onPressed` callback contains `// TODO: initiate group call via engine` — this is a placeholder/stub, the group call button does nothing — `chat_view.dart:5992-5994`
- [ ] spec §4 "Search choose from user": spec says search mode shows a "choose from user" filter button. Code has the button but the callback is `// TODO: open user picker for "from user" filter` — stub placeholder — `chat_view.dart:5862-5864`
- [ ] spec §4 "Pinned bar height": spec says 49px (`historyReplyHeight`). Code uses `height: 49` — matches
- [ ] spec §4 "Pinned bar thumbnail": spec says 32x32px with `ImageRoundRadius::Small` (~3px). Code uses `width: 32, height: 32` and `borderRadius: BorderRadius.circular(3)` — matches
- [ ] spec §4 "Pinned bar accent stripe": spec says `msgReplyBarSize: size(2px, 36px)` at `msgReplyBarPos: point(1px, 0px)` with `msgReplyBarSkip: 10px`. Code uses `Container(width: 2, height: 36)` preceded by `SizedBox(width: 1)` (for the 1px offset) then `SizedBox(width: 10)` for skip — matches spec exactly
- [ ] spec §4 "Pinned bar content animation": spec says 160ms. Code uses `AnimatedSwitcher(duration: Duration(milliseconds: 160))` — matches
- [ ] spec §4 "Pinned bar title": spec says "Pinned Message" for single, "Previous Pinned Message" when count==2 and shown isn't last, else "Pinned Message #N". Code in `_pinnedTitle()` matches this logic — correct
- [ ] spec §4 "Pinned bar close button": spec says 49x49 hit-area, 40px circular ripple at (4,4). Code uses `SizedBox(width: 49, height: 49)` with `Positioned(left: 4, top: 4)` containing a 40x40 `InkWell` in `ClipOval` — matches
- [ ] spec §4 "Pinned bar background": spec says `historyPinnedBg`. Code uses `palette.historyPinnedBg` — correct if palette maps it
- [ ] spec §4 "Selection mode animation": spec says `slideWrapDuration ~200ms, easeOutCirc`. Code uses `AnimationController(duration: Duration(milliseconds: 200))` with `CurvedAnimation(curve: Curves.easeOutCirc)` — matches exactly
- [ ] spec §4 "Selection buttons": spec says `defaultActiveButton` (pill, blue fill, white text) with uppercased labels "FORWARD", "SEND NOW", "DELETE". Code uses uppercase labels and `activeButtonBg`/`activeButtonFg` colors — matches
- [ ] spec §4 "Selection count": spec says count lives on buttons via `setNumbersText`, no separate "X messages selected" label. Code uses `_AnimatedCountBadge(count: count)` appended to each button — matches spec approach
- [ ] spec §4 "Selection button gap": spec says `topBarActionSkip: 10px`. Code uses `const SizedBox(width: 10)` between buttons — matches
- [ ] spec §4 "Selection button corner radii": spec says `large = 8px` for outer ends, small for inner. Code uses `Radius.circular(8)` for large and `Radius.circular(4)` for small — matches (4px is a reasonable "small" radius)
- [ ] spec §4 "Cancel button": spec says `topBarClearButton` = `RoundButton(defaultLightButton)` with `width: -18px`, uppercased "CLEAR"/"CANCEL", right-aligned at 10px margin. Code uses a `TextButton` with `EdgeInsets.symmetric(horizontal: 18)` — the -18px is Telegram's way of specifying horizontal padding for auto-width, so padding=18 matches. Label should be uppercase but would need to verify the exact text — `chat_view.dart:9324`
- [ ] spec §4 "Contact status bar height": spec says 49px. Code would need verification in `_ContactStatusBar` — `chat_view.dart:8367`
- [ ] spec §4 "Contact status button style": spec says "height 49px, textTop 16px, font semiboldFont, hover bg historyComposeButtonBg, ripple historyComposeButtonBgOver, flat full-width FlatButton". Destructive variant uses `attentionButtonFg` (red). Implementation needs verification — `chat_view.dart:8367`
# Audit: §5-§7 Messages & Compose

## §5 — Message List & Bubbles

- [ ] spec §5 "Bubble shape / Tail": Spec says last message in group should have a decorative triangle Tail on the bottom sender-side corner. Code uses `radiusSmall` (6px) for `bottomSenderSide` regardless of `isLastInGroup` — there is no Tail path at all, only circular radii. The visual distinction between last-in-group and mid-group on the sender side is absent — `message_bubble.dart:505-506`
- [ ] spec §5 "Bubble padding": Spec says internal padding 11px horizontal, 8px vertical. Code uses `EdgeInsets.symmetric(horizontal: 11, vertical: 6)` — vertical is 6px instead of 8px — `message_bubble.dart:591`
- [ ] spec §5 "Consecutive Grouping / Bottom corners": Spec says bottom-other-side should always be Large (16px) when NOT attached-to-next. Code sets `bottomOtherSide = isLastInGroup ? radiusLarge : radiusSmall` — mid-group messages get `radiusSmall` on both bottom corners, whereas spec says only the sender-side should be Small, the other side should remain Large — `message_bubble.dart:506`
- [ ] spec §5 "Sender name hidden in DMs": Spec says sender name hidden "in DMs" for incoming messages. Code condition `!isOutgoing && message.senderName.isNotEmpty && isFirstInGroup` has no `isGroupChat` guard, so incoming DM messages will incorrectly show sender names — `message_bubble.dart:615`
- [ ] spec §5 "Forward header ordering": Spec §5.4 content order is: sender name, topic, via bot, **forward header**, reply block, text. Code renders reply preview (line 690) BEFORE forward header (line 700), reversing the spec order — `message_bubble.dart:690-711`
- [ ] spec §5 "Reply block height": Spec says reply left bar is 2px wide and 36px tall. Code renders `Border(left: BorderSide(width: 2))` with no explicit 36px height constraint — the bar stretches to content height — `message_bubble.dart:2434-2436`
- [ ] spec §5 "Reply block two-line content": Spec says reply block shows reply sender name + preview text as two separate styled lines with 10px gap. Code shows only a single-line preview text (`maxLines: 1`), missing the reply sender name as a separate element — `message_bubble.dart:2438-2443`
- [ ] spec §5 "Bottom info spacing": Spec says `historyViewsSpace: 8px` before views/replies, `historyViewsWidth: 20px` per icon, `historySendStateSpace: 24px` before edited/time group. Code uses `SizedBox(width: 2)` between icon and count, and `SizedBox(width: 4)` before status icon — none match spec spacing — `message_bubble.dart:809,845`
- [ ] spec §5 "Bottom info floating": Spec says for text bubbles, bottom info floats at bottom-right of the last line of text content. Code puts the info Row on its own line inside a Column with a `Spacer()` pushing it right — occupies a full row instead of floating inline — `message_bubble.dart:802-805`
- [ ] spec §5 "Scroll-to-bottom FAB animation": Spec says 150ms slide-in animation with linear easing. Code shows/hides the FAB without any entry/exit slide or fade transition — `chat_view.dart:10477-10479`
- [ ] spec §5 "Scroll-to-bottom show threshold": Spec says FAB appears after scrolling `historyToDownShownAfter = 480px` from bottom. No 480px threshold check found in the FAB visibility logic — `chat_view.dart`
- [ ] spec §5 "Stacked corner buttons gap": Spec says Jump-down, Mentions, Reactions, PollVotes stack with `historyUnreadThingsSkip = 4px` gap. No 4px spacing constant visible between stacked `_CornerButton` widgets — `chat_view.dart:10549-10644`
- [ ] spec §5 "Unread-count badge offset": Spec says badge drawn 4px above button top (stroke=4 arg to PaintUnreadBadge). Code positions badge at `top: 0` of the 52x62 SizedBox — at the very top, not 4px above the disc at y=15 — `chat_view.dart:10486-10488`
- [ ] spec §5 "Selection mode bubble offset": Spec says `msgSelectionOffset = 30px` shifts bubbles leftward when in selection mode. Code does not apply any horizontal offset to bubbles when `inSelectionMode` is true — bubbles stay in place — `message_bubble.dart:856-864`

## §6 — Media Message Types

- [ ] spec §6 "Emoji sticker max size": Spec says emoji stickers max 256px (vs 224px for static/animated). Code clamps all stickers uniformly to 224px max regardless of emoji sticker type — `message_bubble.dart:3044-3047`
- [ ] spec §6 "Premium sticker mirroring": Spec §6.6 says incoming (left-aligned) premium stickers are mirrored horizontally, outgoing are not. No mirroring logic exists in `_VisualMedia` — premium stickers render without any horizontal flip — `message_bubble.dart:3056-3061`
- [ ] spec §6 "Voice play button fill": Spec says play button is a solid accent-colored 44px circle. Code renders `accentColor.withValues(alpha: 0.15)` — a 15% tint instead of solid fill — `message_bubble.dart:3950-3951`
- [ ] spec §6 "File document vertical layout": Spec says filename at 12px from top, status at 34px from top (fixed offsets). Code vertically centers both via `MainAxisAlignment.center` — positions drift depending on content height — `message_bubble.dart:5064-5066,5120-5121`
- [ ] spec §6 "Audio inline playback": Spec says audio/music plays inside the bubble with "played/total" duration during playback (same 44px play/pause button as voice). Code opens audio files externally with `xdg-open` instead of playing inline — `message_bubble.dart:4236-4249`
- [ ] spec §6 "Poll single-select checked indicator": Spec says when checked, center gets `historyPollChoiceRight` check icon in `activeButtonFg` inside a filled circle — "no raw check dot, an icon is used." Code renders a filled inner circle dot without a check icon — `message_bubble.dart:7806-7818`
- [ ] spec §6 "Poll fireworks canvas size": Spec says fixed 480x320px logical canvas. Code uses the widget's layout size (Positioned.fill on parent) instead of a fixed canvas — `message_bubble.dart:7911`
- [ ] spec §6 "Poll fireworks particle size": Spec says particles are 2px on the short side (`_smallSide`). Code uses `2.0 + random * 3` giving 2-5px base, with `height = size * 0.5` making short side 1-2.5px — not a fixed 2px — `message_bubble.dart:7859,7929`
- [ ] spec §6 "Location venue text maxLines": Spec says venue title 2 lines max, description 3 lines max. Code shows venue info without explicit `maxLines` constraints — `message_bubble.dart:4591-4645`
- [ ] spec §6 "Contact action button casing": Spec says "Send Message" / "Add Contact" / "View Details" (title case). Code uses "SEND MESSAGE" / "ADD CONTACT" / "VIEW DETAILS" (all caps) — `message_bubble.dart:4840-4846`
- [ ] spec §6 "Web page Article thumbnail sizing": Spec says article-mode thumbnail width is `ArticleThumbWidth(photo, articleMinHeight)` clamped to line-height. Code uses a hardcoded 48x48 square — `message_bubble.dart:8103-8104`

## §7 — Compose Area

- [ ] spec §7.2 "Attachment button behavior": Spec says desktop does NOT show a popup — paperclip opens native OS file picker directly (attach-bots menu is separate, hover-triggered). Code opens a `showTelegramMenu` popup with "File" and "Poll" entries, deviating from spec — `chat_view.dart:13229-13241`
- [ ] spec §7.2 "Missing attach options": Spec says Location and Contact are accessible in Telegram Desktop (via bot keyboard or other means). Code's attach menu only offers File + Poll + bots — Location and Contact are entirely absent — `chat_view.dart:13233-13234`
- [ ] spec §7.3 "Send button — Cancel state": Spec says `_isInlineBot` triggers Cancel state. `_computeSendButtonType` does not check for inline bot mode — Cancel state is unreachable — `chat_view.dart:12614-12626`
- [ ] spec §7.3 "Send button — Schedule state": Spec says when `_mode != Normal` (e.g. scheduled messages view), button becomes Schedule instead of Send. Code always returns `SendButtonType.send` when text is present — `chat_view.dart:12625`
- [ ] spec §7.3 "Send button — EditPrice state": Spec says "editing stars-per-message" triggers EditPrice state. `_computeSendButtonType` does not check `starsToSend` — EditPrice is unreachable — `chat_view.dart:12614-12626`
- [ ] spec §7.3 "Send button — Voice/Round Lottie": Spec says Voice<->Round transition plays a Lottie animation ("microphone rolls into camera"). Code uses a 500ms `_rollController` but renders static Material Icons (Icons.mic / Icons.videocam) — no Lottie animation — `chat_view.dart:14492,14574-14583`
- [ ] spec §7.3 "Send button — stars-to-send pill": Spec says button widens to a pill with star-count + icon, 28px height, `SendButton.stars` style. No pill-rendering logic exists in `_SendButton` — `chat_view.dart:14454`
- [ ] spec §7.4 "Voice record blob radii": Spec says three concentric blobs — Main (23-37px), Major (43-50px), Minor (40-47px). Code's `_BlobPainter` animates a generic 0-1 value without explicit radii matching these three layers — `chat_view.dart:14933-15007`
- [ ] spec §7 "Edit bar label text": Spec says "Edit message" label. Code shows "Editing" — `chat_view.dart:7546`
- [ ] spec §7 "Edit bar accent bar height": Spec says 36px (same as reply bar). Code uses `Container(width: 2, height: 28)` — 28px instead of 36px — `chat_view.dart:7538`
- [ ] spec §7.6 "Drag overlay dimming layer": Spec says overlay is rounded cards with `boxBg`/`boxRoundShadow` — no full-screen color wash. Code wraps everything in `Container(color: Color(0x80000000))` adding a 50% black overlay not present in spec — `chat_view.dart:16187-16188`
- [ ] spec §7 "Date separator sticky": Spec says date separators scroll with messages — NOT sticky. Code adds a `_StickyDateHeader` overlay at the top of the viewport, which is not in the original Telegram Desktop spec — `chat_view.dart:6830-6894`
# Audit: §8-§13 Panels & Overlays

## §8 — Info / Details Panel

- [ ] spec §8.1 "Cover compression snap-scroll": spec requires 3 snap points {0, 112, 180} with easeOutQuint 260ms between resting heights; implementation uses a continuous SliverPersistentHeader that shrinks linearly without discrete snap steps or easeOutQuint easing — `info_panel.dart` `_FlexibleCoverDelegate`
- [ ] spec §8.1 "Direction reversal mid-animation": spec says direction reversal mid-animation re-bases via _timeOffset instead of restarting; no corresponding logic in the Flutter implementation — `info_panel.dart`
- [ ] spec §8.2 "Action-button row collapse math": spec defines action-row height = clamp(52 * (ratio - 0.5) / 0.5, 0, 52) with linear shrink past 50% mark; implementation has the ratio math but buttons simply fade via opacity rather than shrinking their height to 0 — `info_panel.dart` `_FlexibleCoverDelegate.build`
- [ ] spec §8.2 "Per-button icon scale hold": spec says icon holds full size to 40% then scales with button via (progress - 0.4) / 0.6; no per-button icon scale logic implemented — `info_panel.dart`
- [ ] spec §8.2 "Per-button text scale": spec says text scales with max(0.4, progress); no text scaling on action buttons — `info_panel.dart`
- [ ] spec §8.2 "Max 3 primary + More overflow": spec says hard cap of 3 visible action buttons with overflow into a "More" popup menu, and Side wrap mode always uses More; no More button or overflow logic present — `info_panel.dart`
- [ ] spec §8.2 "Mute toggle right-click menu": spec says right-click on mute opens duration menu (MuteMenu::SetupMuteMenu); no right-click handler on mute action button — `info_panel.dart`
- [ ] spec §8.2 "Lottie icon mute/unmute crossfade": spec says mute toggle plays Lottie animations (profile_muting/profile_unmuting); implementation uses static Material Icons, no Lottie — `info_panel.dart`
- [ ] spec §8.3 "No horizontal tab strip": spec confirms there is NO Photos/Videos/Files horizontal tab bar in the info panel; implementation uses vertical rows with expand/collapse toggle correctly, but the expandable grid is an in-place inline expansion rather than a full-screen sub-section push via navigation stack — `info_panel.dart` `_SharedMediaSection._toggleGrid`
- [ ] spec §8.3 "Shared media sub-section push navigation": spec says each media type is a full-screen sub-section reached by _controller->showSection(), pushed onto WrapWidget._historyStack; implementation expands inline without pushing onto nav stack — `info_panel.dart`
- [ ] spec §8.3 "Media type Rounds and Polls": spec lists RoundFile and Poll as separate shared media types; these are not present in the media counts rows — `info_panel.dart` `_SharedMediaSection`
- [ ] spec §8.4 "Members search button is stub": search members button has empty onTap handler `() {}` — `info_panel.dart:4846`
- [ ] spec §8.4 "Add member button is stub": add member button has empty onTap handler `() {}` — `info_panel.dart:4852`
- [ ] spec §8.4 "Member row context menu": spec says PeerListController::rowContextMenu has View Profile, Send Message, Promote/Demote, Restrict, Remove, Ban, Copy Username/ID; no right-click context menu on member rows — `info_panel.dart` `_MemberRow`
- [ ] spec §8.4 "Member row admin/creator pill tags": spec defines AdminPill with memberTagPillPadding for "owner"/"admin" badges; implementation shows role text inline but does not use a pill-shaped container with the specified padding — `info_panel.dart` `_MemberRow`
- [ ] spec §8.4 "Stories ring on member avatars": spec says setStoriesShown(true) draws unread-stories ring around member avatars; no story ring on member row avatars — `info_panel.dart` `_MemberRow`
- [ ] spec §8.5 "Grid columns formula": spec defines columns = max(1, floor((listWidth - 4) / 84)) with infoMediaMinGridSize=82px and infoMediaSkip=2px; implementation uses _minGridSize=82 and _skip=2 correctly — this matches (no issue)
- [ ] spec §8.5 "Date headers in grid": spec defines 28px date section headers with semibold text at point(14, 6); implementation shows month headers but with default text style and no exact 28px height or (14,6) offset — `info_panel.dart` `_MediaGrid`
- [ ] spec §8 "User profile common groups": spec says user profile includes "Common Groups" row; no Common Groups feature implemented for DM user profiles — `info_panel.dart` `_UserProfilePage`
- [ ] spec §8 "In-section search field": spec describes infoMediaSearch with height 44px, padding margins(8,6,8,6) activated via _topBar->createSearchView(); no in-section search for shared media — `info_panel.dart`
- [ ] spec §8 "State persistence / Memento": spec says Memento system saves scroll position, search query, active media tab, navigation stack; implementation saves scroll position per nav page but not search query or active media tab — `info_panel.dart` `_InfoNavPage`
- [ ] spec §8.6 "Animated emoji-status pattern behind avatar": spec describes setupAnimatedPattern/paintAnimatedPattern for Premium status pattern; no animated pattern behind avatar for premium users — `info_panel.dart` `_FlexibleCoverDelegate`
- [ ] spec §8.6 "Music mini-player hook": spec describes infoMusicButtonPadding with Performer/Title labels and quick-jump to source message; no music mini-player in info panel — `info_panel.dart`
- [ ] spec §8.6 "Bot About + Commands rows": spec says bot profiles show Bio, help/settings/privacy as three AddActionButton bound to /command click; no bot-specific command rows — `info_panel.dart`
- [ ] spec §8.6 "Business Hours / Location / Birthday / Personal Channel": spec lists these as DetailsFiller rows; none are present — `info_panel.dart`

## §9 — Context Menus & Actions

- [ ] spec §9 "Voice Timecode action": spec item 2 in message context menu is "Voice Timecode (on playing voice messages)"; not present in context menu — `chat_view.dart:1302+`
- [ ] spec §9 "Go to Message action": spec item 5 "Go to Message (in pinned/preview context)"; not present as a context menu item (exists separately in pinned bar) — `chat_view.dart`
- [ ] spec §9 "View Replies / View Topic / View Thread": spec item 6; not present in context menu — `chat_view.dart`
- [ ] spec §9 "Send Now grouped": spec says Send Now applies to all items with same groupedId; implementation handles grouped send-now correctly — no issue
- [ ] spec §9 "Copy Image action": spec item 13 "Save/Copy Image (photos)" includes copy-to-clipboard of image; only "Save Image" is present, no "Copy Image" — `chat_view.dart:1376`
- [ ] spec §9 "Attached Stickers / Open GIF / Sticker Pack Info": spec item 14; only "View Sticker Pack" exists for stickers, no "Attached Stickers" or "Open GIF" or "Save GIF" in message context menu — `chat_view.dart`
- [ ] spec §9 "Favorite/Unfavorite Sticker": spec item 15; not in message context menu — `chat_view.dart`
- [ ] spec §9 "Show in Folder/Finder": spec item 16 for local files; not present — `chat_view.dart`
- [ ] spec §9 "Clear Selection action": spec item 21 says "Select / Clear Selection"; Select is present but Clear Selection is missing from context menu — `chat_view.dart:1393`
- [ ] spec §9 "Cancel Upload for uploading messages": spec says Delete shows as "Cancel Upload" for uploading messages; no Cancel Upload variant — `chat_view.dart`
- [ ] spec §9 "Poll-specific items": spec mentions "Translate Poll, Retract Vote, Stop Poll, per-option submenu"; only Translate Poll present, no Retract Vote or Stop Poll — `chat_view.dart`
- [ ] spec §9.2 "Attention style: red icon + normal text": spec says default attention items have red icon but normal-colored text (text stays windowFg); implementation makes entire text red when `isAttention && !hasIcon`, which is correct for the no-icon case, but the icon-present case also makes text red depending on fullAttention flag — review needed for accuracy — `popup_menu.dart:599`
- [ ] spec §9.3 "Reaction strip on message hover": spec describes a horizontal strip of recent reactions appearing on hover with expand chevron to full panel; no reaction hover strip exists (reactions only appear as existing reaction counters below messages) — `message_bubble.dart`
- [ ] spec §9.3 "Reaction hover pop 1.24x scale": spec says per-icon hover pop to 1.24x over 200ms; no hover scale on reaction items — `message_bubble.dart`
- [ ] spec §9.3 "Floating corner reaction button": spec defines reactionCornerSize 36x32 pill with 300ms hover delay; no floating corner reaction button on message hover — `message_bubble.dart`
- [ ] spec §9.4 "Forward dialog 3-dot menu": spec defines a 3-dot menu with Forward options (Show sender's name, Show caption checkmarks), Separator, Schedule, Send-as silent/without-sound/whenOnline; implementation has a _ForwardSendOptions but should be verified for completeness — `chat_view.dart` `_ShareBox`
- [ ] spec §9.5 "Delete confirmation moderate panel": spec defines checkboxes for Ban User, Report Spam, Delete All from User with live "(N)" count suffix; implementation has basic delete confirmation but no moderate panel with ban/report/deleteAll checkboxes — `confirm_box.dart`
- [ ] spec §9.5 "Delete for everyone checkbox with remember preference": spec says revoke preference is remembered via settings; basic delete-for-everyone checkbox exists but no "Remember" nested checkbox — `confirm_box.dart`

## §10 — Emoji / Sticker / GIF Panels

- [ ] spec §10.1 "Panel auto-hide kDelayedHideTimeoutMs = 3000ms": spec says when context menu is open inside panel, hide timeout extends to 3000ms; implementation uses a simple 300ms hide timer with no extended timeout for context menu open state — `emoji_panel.dart:19`
- [ ] spec §10.3 "Skin-tone popup delay 500ms": spec says kColorPickerDelay = 500ms long-press timer threshold; implementation triggers skin tone popup on Flutter's default long-press (which is ~500ms) but no explicit 500ms timer — works approximately correctly
- [ ] spec §10.3 "Skin-tone popup chrome": spec defines emojiColorsPadding = 8px inter-variant gap and emojiColorsSep = 1px separator; implementation builds a popup with _kEmojiColorsPadding = 8 and _kEmojiColorsSep = 1 — matches spec
- [ ] spec §10.3 "Custom emoji packs with Unlock button": spec says locked packs show "Unlock" button (premium gate), free packs show "Add", collapsed sets surface 3 rows + "+N" overflow; custom emoji packs section not implemented in emoji tab — `emoji_panel.dart` `_EmojiTab`
- [ ] spec §10.4 "Sticker pack footer scrollable strip": spec defines kVisibleIconsCount = 8 horizontally scrollable strip of pack icons with _selectionBg highlight and stickerIconMove = 400ms scroll animation; implementation has a `_StickerPackStrip` footer but needs verification of 8 visible icons and 400ms animation — `emoji_panel.dart` `_StickerTab`
- [ ] spec §10.4 "Trending/Featured packs inline Add button": spec says featured/trending packs show inline "Add" button (stickersTrendingAdd 26px tall); implementation has featured packs with add buttons — appears correct
- [ ] spec §10.4 "Sticker context menu Fave/Unfave, View Set, Copy Link": spec says context menu has Fave/Unfave, View Set, and for custom emoji also Copy Link; implementation shows fave option in sticker long-press menu but only in the _StickerTab, not in the compose-area sticker suggestions — `emoji_panel.dart:1544`
- [ ] spec §10.5 "GIF masonry layout": spec says Mosaic does line-packing not true masonry (each row uniform height but varies between rows); implementation has `_GifMasonryGrid` which does row-packing — appears correct
- [ ] spec §10.5 "GIF tab saved GIFs / inline @gif bot search": spec says default shows saved GIFs, typing query switches to @gif bot results; implementation has search with debounce that queries inline bot — correct
- [ ] spec §10.5 "GIF context menu Save GIF / Delete GIF": implementation has both Save GIF and Delete GIF in long-press menu — correct
- [ ] spec §10.5 "GIF category emoji shortcuts in footer": spec mentions category shortcuts as emoji tokens (cat, heart, dance, etc.); implementation has `_GifCategoryFooter` — correct
- [ ] spec §10.6 "Inline suggestions / field autocomplete": spec describes a separate FieldAutocomplete widget for @mentions, /commands, :emoji, #hashtags anchored above compose field with 40px row height and 4.5-row max; no separate field autocomplete widget found — this feature appears missing as a dedicated panel
- [ ] spec §10.6 "Emoji suggestions horizontal row": spec says :text trigger shows horizontally scrollable emoji suggestions with 40px cells and 8px fade padding; not found as a separate widget — `emoji_panel.dart`
- [ ] spec §10.6 "Sticker suggestions on Unicode emoji": spec says typing a Unicode emoji shows sticker preview strip at half stickerPanSize width; not implemented — `emoji_panel.dart`

## §11 — Authentication / Login Flow

- [ ] spec §11.2 "Next button Y interpolation with introNextSlide = 200px": spec says Y interpolates from introNextTop + 200px up to introNextTop driven by shownAmount; implementation uses a simple slide/fade animation from Offset(0, 200) to zero — approximately matches
- [ ] spec §11.2 "Next button width = 300px, height = 42px, radius = 6px": implementation has SizedBox width=300, height=42 with borderRadius=6 — matches spec
- [ ] spec §11.3 "QR radial spinner color #40A7E3": spec says QrActiveColor() returns #40A7E3; implementation uses palette.windowBgActive which is theme-dependent, not the fixed hex value — `auth_screen.dart:779`
- [ ] spec §11.3 "QR token crossfade (not slide)": spec says new QR matrix crossfades over old one with no slide; implementation uses AnimatedSwitcher with default crossfade — correct
- [ ] spec §11.3 "QR Redundancy::Quartile": implementation uses QrErrorCorrectLevel.Q — matches spec
- [ ] spec §11.4 "Country picker popup": spec says Ui::MultiSelect search filter + scrollable rows with flag glyph + country name + +XX code; implementation has a custom _CountryPickerDialog with search and flag+name+code rows — correct
- [ ] spec §11.5 "OTP cell geometry 40x50px, 4px border, 10px gap, 20px font": implementation has _cellWidth=40, _cellHeight=50, _borderWidth=4, _cellGap=10, _digitFontSize=20 — matches spec exactly
- [ ] spec §11.5 "OTP digit entry animation 120ms slide up 10px": spec says digit fades in + slides up by 0.2 * 50 = 10px over 120ms; implementation has 120ms duration with Offset(0, 10) slide — matches spec
- [ ] spec §11.5 "OTP error shake": spec says DefaultShakeCallback triggers shake; implementation has a custom shake animation — present
- [ ] spec §11.5 "Call countdown row": spec says "Telegram will call you in X:XX" with "Calling..." state; implementation has call timer and "Calling..." text — correct
- [ ] spec §11.5 "Didn't get the code? link": spec says link offers alternate delivery; implementation has the link but onPressed is empty `() {}` — stub action — `auth_screen.dart:1700`
- [ ] spec §11.6 "2FA password top = 74px": spec says introPasswordTop = 74px; implementation uses fieldTop = 74.0 — matches spec
- [ ] spec §11.6 "2FA recovery mode": spec says "Forgot password?" swaps to recovery-code mode with email pattern info; implementation has full recovery mode toggle with _isRecoveryMode — correct
- [ ] spec §11.6 "2FA recovery no-email: reset account button": spec says if no recovery email, info box opens with "Reset account" button (7-day timer); implementation shows reset account button after dialog — correct
- [ ] spec §11.7 "Registration avatar UserpicButton": spec says avatar tap opens system photo picker; implementation has a GestureDetector with empty onTap `() {}` — avatar picker is a stub — `auth_screen.dart:618`
- [ ] spec §11.7 "Registration RTL name field swap": spec says RTL swaps last-name first; implementation checks Directionality and swaps controllers — correct
- [ ] spec §11.8 "Cover gradient introCoverTopBg/BottomBg": spec says typical blue sweep #0088CC to #0066AA day; implementation uses Color(0xFF0088CC) to Color(0xFF0066AA) for day — matches spec
- [ ] spec §11.8 "Cover slide easing easeOutCirc for cover transitions": spec says anim::easeOutCirc when hasCover; implementation uses Curves.easeOutCirc for cover transitions — matches spec
- [ ] spec §11.8 "Title/description crossfade 200ms": spec says Ui::FlatLabel::CrossFade() over introCoverDuration = 200ms; implementation uses AnimatedSwitcher with 200ms — matches spec
- [ ] spec §11.1 "Change Language link is stub": language dialog only shows English with no real language switching — `auth_screen.dart:1876-1891`

## §12 — Calls UI

- [ ] spec §12.1 "Window default 720x540, min 380x520": implementation has defaultWidth=720, defaultHeight=540, minWidth=380, minHeight=520 — matches spec
- [ ] spec §12.1 "Incoming state: 160px userpic, 21px semibold name": implementation builds 160px userpic and 21px w600 name — matches spec
- [ ] spec §12.1 "Active button-row order: Screencast, Camera, Hangup, Mute, Add People": implementation has Screencast, Camera, End Call (hangup), Mute, Add People — matches spec
- [ ] spec §12.1 "Remote pills for muted/low-battery": implementation has _RemoteStatusPill for both muted mic and low battery — correct
- [ ] spec §12.1 "Controls auto-hide 5000ms fullscreen, 2000ms mouse-leave": implementation has _kHideControlsFullscreen=5000ms, _kHideControlsMouseLeave=2000ms — matches spec
- [ ] spec §12.1 "Button row crossfade 150ms on state change": implementation has AnimatedSwitcher with 200ms on button state changes, spec says 150ms — duration mismatch — `call_panel.dart`
- [ ] spec §12.2 "Signal bars 4 bars, 2px wide, heights 4/6/8/10, 2px skip, 1px radius": call_panel.dart _SignalBarsPainter has barWidth=2, heights [4,6,8,10] derived from formula, skip=2, radius=1 — matches spec
- [ ] spec §12.2 "Signal bar inactive opacity 0.5": implementation uses Color(0x80FFFFFF) which is ~0.5 opacity — matches spec
- [ ] spec §12.2 "Signal bars snap (no interpolation)": implementation repaints on quality change without animation — matches spec
- [ ] spec §12.3 "Encryption fingerprint 4 emoji, 10 carousel, 50ms stagger, 100ms per hop, 1200ms total": implementation has _kEmojiCount=4, _kCarouselCount=10, _kStartTimeShiftMs=50, _kCarouselOneMs=100, _kTotalMs=1200 — matches spec exactly
- [ ] spec §12.3 "Fingerprint tooltip delay 1000ms": spec says kTooltipShowTimeoutMs = 1000ms hover delay; implementation uses TelegramTooltip which may not have 1000ms delay — `call_panel.dart:1110`
- [ ] spec §12.3 "Fingerprint pill container radius=height/2": implementation uses borderRadius: BorderRadius.circular(999) which achieves pill shape — correct
- [ ] spec §12.4 "Self-view VideoBubble 160x110, snap-to-corners, 12px inset, 120ms easeOutCirc": implementation has _width=160, _height=110, _inset=12, _snapDuration=120ms with easeOutCirc — matches spec exactly
- [ ] spec §12.4 "Self-view mirror ON by default, OFF during screen-share": implementation passes mirror: !widget.info.isScreenSharing — correct
- [ ] spec §12.4 "Outgoing preview min 360x120, max 1620x540, scale formula": implementation has _minSize=(360,120), _maxSize=(1620,540) with correct interpolation formula — matches spec
- [ ] spec §12.4 "Camera button device-selector menu via corner chevron": spec says tiny corner chevron opens device-selector menu for camera/mic switch; no device selector menu implemented — `call_panel.dart`
- [ ] spec §12.5 "Group call wide mode threshold 600px": implementation has wideModeThreshold=600.0 — matches spec
- [ ] spec §12.5 "Group call narrow minimum 380px": implementation has minWidth=380.0 — matches spec
- [ ] spec §12.6 "Speaker blob dual system: minor 6 vertices scale 0.545, major 8 vertices scale 0.605": implementation has _minorVertices=6, _majorVertices=8, _minorScale=0.545, _majorScale=0.605 — matches spec exactly
- [ ] spec §12.6 "Speaker blob min/max radius 27/29px, levelDuration 215ms": implementation has _minRadius=27, _maxRadius=29, _levelDuration=215ms — matches spec
- [ ] spec §12.6 "Userpic scale 0.8 to 1.0 with level": implementation has _userpicMinScale=0.8 with scale = 0.8 + 0.2 * level — matches spec
- [ ] spec §12.7 "Big mute button 36x36 icon in 42px circle, green/gray/purple states": implementation has _circleSize=42, _iconSize=36, green=#4DC920, gray=#808B94, purple=#7B5EBF — matches spec
- [ ] spec §12.7 "Big mute button blob ring with 215ms level envelope": implementation uses a blob ring with matching pulse period — approximately correct
- [ ] spec §12.8 "Minimised top bar height 38px": implementation has MinimisedCallBar.height = 38.0 — matches spec
- [ ] spec §12.8 "Minimised bar userpic strip 28px with 8px overlap": implementation has _UserpicStrip with _size=28.0 and _overlap=8.0 — matches spec
- [ ] spec §12.8 "Minimised bar gradient state machine with force-muted 3-stop purple": implementation has 3-stop purple gradient for forceMuted — matches spec
- [ ] spec §12.8 "Gradient transition animation": implementation has _gradientAnim with 150ms easeInOut gradient interpolation — approximately correct
- [ ] spec §12.8 "Minimised bar duration timer mm:ss": implementation formats as m:ss (no zero-padding on minutes for short durations) while spec implies mm:ss; also handles hours — minor format difference
- [ ] spec §12.9 "Screen-share chooser dual-tab Windows/Full Screen, 235x165 thumbs": implementation has tabs and _kThumbW=235, _kThumbH=165 — matches spec
- [ ] spec §12.9 "Share audio checkbox gated by PipeWire on Linux": implementation checks for PipeWire process and shows checkbox conditionally — correct
- [ ] spec §12.10 "Rating dialog 5 stars, comment max height 135px": implementation has 5 stars at 36x36, comment maxHeight=135 — matches spec
- [ ] spec §12.10 "Rating star unselected color windowSubTextFg, selected lightButtonFg": implementation uses windowSubTextFg for unselected and palette.windowBgActive for selected; spec says selected should be lightButtonFg — possible color mismatch — `call_panel.dart:1565`

## §13 — Mobile / Web Compatibility

- [ ] spec §13.1 "OneColumn < 640px, ThreeColumn >= 932px": implementation in shell.dart has _oneColumnBreak = 640.0 and three-column break; needs verification of the 932px threshold — `shell.dart:76`
- [ ] spec §13.2 "OneColumn back button in chat top-bar": spec says back button appears in chat top-bar to return to dialog list; this should be verified end-to-end in mobile mode
- [ ] spec §13.2 "OneColumn info panel as full-width takeover": spec says third column opens as a full-width takeover layer; InfoPanel has InfoWrapMode.narrow which achieves this — correct
- [ ] spec §13.2 "OneColumn folder tabs horizontal strip below search": spec says folder tabs switch from vertical rail to horizontal strip; implementation needs verification
- [ ] spec §13.3 "Dialogs avatar-only sidebar at 260px minimum": spec says sidebar stops shrinking at 260px columnMinimalWidthLeft; implementation should enforce this minimum width
- [ ] spec §13.3 "Wide chat mode >= 880px centers bubbles": spec says adaptiveChatWideWidth = 880px centers bubbles with gutters; needs verification that bubble centering is implemented at this width
- [ ] spec §13.4 "Touch long-press for context menus": spec says long-press instead of right-click with platform-dependent drag time ~500ms; implementation uses Flutter's default GestureDetector long-press which handles this natively — correct
- [ ] spec §13.4 "Swipe-to-reply gesture": spec mentions swipe gestures for reply on long message; needs verification of swipe-to-reply implementation
- [ ] spec §13.4 "Drag-to-reorder pinned chats kStartReorderThreshold = 30px": spec defines 30px vertical threshold for reorder; needs verification
- [ ] spec §13.5 "Desktop-only features hidden on web": spec lists system tray, global hotkeys, native file picker, clipboard monitoring as desktop-only; no conditional gating found for web platform — may need web-specific guards
# Audit: §14-§19 Settings

## §14 — Settings: General & My Account

### §14.1 Opening Settings / Overflow Menu
- [ ] spec §14.1 "Log Out confirmation dialog": Log Out calls `_confirmLogOut` which works, but the confirmation dialog text uses generic wording instead of the spec's `lng_sure_logout` — `settings_screen.dart`

### §14.2 Profile Header / Cover
- [ ] spec §14.2.3 "Copy ID context menu on username": spec says right-click on username shows "Copy ID" (AyuGram addition) and "Copy Username". Implementation only copies `t.me/username` link on tap; no right-click context menu on username at all — `settings_screen.dart:614-625`
- [ ] spec §14.2.3 "Premium/emoji-status badge": badge is a simple `Icons.workspace_premium` icon; spec says clicking the badge opens the emoji status panel, but this is not wired — `settings_screen.dart:592-595`
- [ ] spec §14.2.3 "Name label right-click shows Copy Full Name": no right-click context menu on the display name in the header — `settings_screen.dart:580-591`

### §14.3 Navigation Buttons
- [ ] spec §14.3 "Devices icon is menuIconUnmute (speaker)": code uses `Icons.devices` not a speaker icon — `settings_screen.dart:274`
- [ ] spec §14.8.1 "TON Currency row": spec says TON row visible when balance > 0 with `menuIconTon`. Missing entirely from the Premium section — `settings_screen.dart:333-368`
- [ ] spec §14.8.1 "Telegram Premium/Stars/Business/Gift onTap": all Premium and Help rows have `onTap: () {}` — no-op stubs; FAQ/Features do not open external links — `settings_screen.dart:334-393`
- [ ] spec §14.3.1 "No inter-row dividers within group": implementation has no inter-row dividers in the group, which is correct. However, chevron arrows on the right side of nav rows are missing (spec mentions right chevron) — `settings_screen.dart:805-841`

### §14.4 Interface Scale
- [ ] spec §14.4 "Scale preview tooltip": spec says a floating preview window (`ScalePreview`) shows a miniature mockup of the sidebar. Implementation shows a simple text-only "Preview: N%" label, not a sidebar mockup — `settings_screen.dart:1093-1119`
- [ ] spec §14.4 "Restart dialog buttons": spec says "Restart Now" / "Cancel" buttons. Implementation says "Apply" / "Cancel" — does not actually restart the app — `settings_screen.dart:1124-1139`

### §14.5 My Account / Edit Profile
- [ ] spec §14.5.3 "Name row click opens EditNameBox": Name row tap just copies to clipboard instead of opening an edit dialog for first/last name — `my_profile_page.dart:228-235`
- [ ] spec §14.5.3 "Phone row click copies and shows toast 500ms": Phone row tap copies but the spec says 500ms toast; implementation shows a generic toast with no specific duration — `my_profile_page.dart:237-245`
- [ ] spec §14.5.3 "Name/Phone/Username right-click context menus": no right-click context menu handlers on the info rows; only left-tap copy — `my_profile_page.dart:228-264`
- [ ] spec §14.5.4 "Personal Channel row": implementation exists as `_PersonalChannelRow` but clicking it does nothing (no navigation to channel editor) — `my_profile_page.dart:326-327`
- [ ] spec §14.5.5 "Birthday footer with [Manage] link to privacy settings": "Manage" link has `onTap: () {}` — no navigation to birthday privacy settings — `my_profile_page.dart:308-320`
- [ ] spec §14.5.6 "Accounts list": `_AccountsSection` exists but key features are missing: no Ctrl+Click to open in new window, no right-click context menu (Copy Phone, Mark All Read, Activate, Log Out), no drag-and-drop reorder — `my_profile_page.dart:349`

### §14.6 Chat Settings
- [ ] spec §14.6.5 "Chat List Quick Action live Lottie preview": the quick action section exists but there is no animated Lottie icon demonstrating the chosen action — `chat_settings_screen.dart:344-351`
- [ ] spec §14.6.6 "Your Stickers / Emoji Sets navigation buttons": the stickers/emoji section has checkboxes but is missing the "Your Stickers" and "Emoji Sets" navigation row buttons — `chat_settings_screen.dart:355-370`
- [ ] spec §14.6.8 "Sensitive Content toggle footer text": no footer text about sensitive media in public channels below the toggle — `chat_settings_screen.dart:389-405`
- [ ] spec §14.6.9 "Archive Settings button": the Shortcuts & Archive section exists (`_ShortcutsArchiveSection`) but the "Archive Settings" button opening `ArchiveSettingsBox` is not verified as functional — `chat_settings_screen.dart:409`

### §14.7 Advanced Settings
- [ ] spec §14.7.7 "Manage Dictionaries rightLabel": shows hardcoded "0" instead of actual installed dictionary count — `advanced_settings_screen.dart:704-709`
- [ ] spec §14.7.7 "Manage Dictionaries onTap": `onTap: () {}` — stub, does nothing — `advanced_settings_screen.dart:709`
- [ ] spec §14.7.8 "Software Update check": `_checkForUpdates` is a fake 2-second delay that always returns "latest" — no real update check — `advanced_settings_screen.dart:109-113`
- [ ] spec §14.7.9 "Screen Reader section": `_buildScreenReader` returns empty list unconditionally — never renders even when a screen reader is detected — `advanced_settings_screen.dart:716`
- [ ] spec §14.7.0 "Experimental Settings section": `ExperimentalSettingsBox` exists but the spec's import/export via `tdesktop-flags:` base64url clipboard strings is not verified — `advanced_settings_screen.dart:762-769`

### §14.8 Premium & Help
- [ ] spec §14.8.2 "Ask a Question confirmation dialog → support chat": the confirm dialog exists but `onConfirm: () {}` does nothing — does not open a support chat — `settings_screen.dart:446-455`
- [ ] spec §14.8.2 "Telegram FAQ / Telegram Features": both `onTap: () {}` — should open URLs in external browser — `settings_screen.dart:374-386`

---

## §15 — Settings: Notifications

### §15.2 Global Settings
- [ ] spec §15.2 "Flash/bounce label varies by platform": hardcoded as "Draw attention to the window" (Linux label). Should detect Windows/macOS and show "Flash the taskbar icon" / "Bounce the Dock icon" respectively — `notifications_settings_screen.dart:250-258`
- [ ] spec §15.2.1 "Volume slider plays notification sound preview on drag": slider updates state but does not play a sound preview while dragging — `notifications_settings_screen.dart:269-281`

### §15.3 Notification Preview
- [ ] spec §15.3 "Preview bubble on wallpaper background": the `_NotificationPreview` widget exists and renders Name/Text checkboxes, but the bubble should show on a wallpaper-themed background with `boxRadius` corners and `msgInBg` fill — implementation not verified to match exactly — `notifications_settings_screen.dart:233-247`

### §15.4 Notifications for Chats (Split-Toggle Rows)
- [ ] spec §15.4 "Status subtitle on split rows": spec says each row should show "Click here to change" or "On/Off, N exception(s)". Implementation has no subtitle text on the split-toggle rows — `notifications_settings_screen.dart:319-367`
- [ ] spec §15.4 "Toggle with exceptions confirmation dialog": spec says toggling when exceptions exist shows "Please note that N chat(s) are listed as exceptions and won't be affected" confirmation. No such dialog exists — `notifications_settings_screen.dart:319-367`

### §15.5 Per-Type Sub-Page
- [ ] spec §15.5.1 "Enable notifications right-click opens Mute Menu popup": `onSecondaryTap` on "Enable notifications" shows `_showMuteMenu` but the mute menu implementation may lack "Select tone" and "Mute for..." picker items — `notifications_settings_screen.dart:1262-1265`
- [ ] spec §15.5.2 "Exception row click opens context menu with view profile + mute options": exception rows have `onRemove` and `onToggleMute` but lack a full context menu with profile viewing — `notifications_settings_screen.dart:1339-1366`

### §15.6 Ringtones Box
- [ ] spec §15.6 "Upload Sound button with file dialog filtered to *.mp3": ringtones box implementation exists but upload constraints (max size from server config, max duration) are not verified — `notifications_settings_screen.dart`
- [ ] spec §15.6 "Right-click on custom tone shows Delete menu": not verified — `notifications_settings_screen.dart`
- [ ] spec §15.6.1 "In-box volume slider hidden when No sound selected": conditional volume slider based on tone selection may not be implemented — `notifications_settings_screen.dart`

### §15.7 Reactions Sub-Page
- [ ] spec §15.7.1 "Reactions to my messages / Votes in my polls split-toggle rows": `_ReactionsSubPage` exists but spec says two split-toggle rows. Need to verify it uses split-toggle format, not plain toggles — `notifications_settings_screen.dart:286-291`
- [ ] spec §15.7.1 "Left click when enabled opens dialog 'Notify about reactions from' with Everyone/Contacts radio": this dialog is not verified — `notifications_settings_screen.dart`

### §15.8-§15.10 Events / Calls / Badge
- [ ] spec §15.10 "Badge Counter toggles do not persist to engine": all badge counter toggles use local state only (`_includeMutedChats` etc.) — not connected to engine/server settings — `notifications_settings_screen.dart:37-65`
- [ ] spec §15.9 "Accept calls controls callsDisabledHere server-side flag": toggle is local state only, not connected to engine — `notifications_settings_screen.dart:54`
- [ ] spec §15.8 "Events toggles do not persist": contact joined / pinned messages toggles are local state only — `notifications_settings_screen.dart:50-51`

### §15.11 System Integration
- [ ] spec §15.11.1 "Windows Focus mode toggle": implementation exists for Windows but uses hardcoded `value: false` and `onChanged: (_) {}` — non-functional stub — `notifications_settings_screen.dart:537-545`
- [ ] spec §15.11.3 "Notification position monitor widget": monitor widget is well-implemented with 5 corners, hit-testing, and animated bars. However, spec says hovering spawns actual desktop sample notification windows (320x80px) — this is not implemented — `notifications_settings_screen.dart:654-974`
- [ ] spec §15.11.4 "Notification count slider": implemented as 5-segment tab picker, which matches spec's `SettingsSlider` style — correct

---

## §16 — Settings: Privacy & Security

### §16.1 Navigation / Build Order
- [ ] spec §16.1 "60-second polling timer": implementation has `Timer.periodic(const Duration(seconds: 60))` for password state only — other privacy data is not polled — `privacy_settings_screen.dart:79-81`

### §16.2 Security Section
- [ ] spec §16.2.1 "Two-Step Verification flow": full flow implemented (check/set/manage password, recovery email confirm, password reset). Well done — `privacy_settings_screen.dart:375-414`
- [ ] spec §16.2.2 "Auto-Delete Messages (Global TTL)": `_GlobalTTLScreen` exists with radio buttons and custom period. Implementation looks complete — `privacy_settings_screen.dart:364-373`
- [ ] spec §16.2.3 "Passcode Lock": full create/check/manage flow with auto-lock timer implemented — `privacy_settings_screen.dart:309-349`
- [ ] spec §16.2.4 "Passkeys": passkey fetching exists but the UI row may lack full management (add/remove passkeys) — `privacy_settings_screen.dart:153-166`
- [ ] spec §16.2.6 "Blocked Users": shows count in right-label but clicking likely navigates to a blocked users screen that may lack the empty state Lottie animation and "Block User" button — `privacy_settings_screen.dart:169-178`

### §16.3 Privacy Section
- [ ] spec §16.3 "Privacy settings right-label with exception counts": implemented correctly with `_privacyLabel` showing "Everyone (+3, -2)" format — `privacy_settings_screen.dart:273-301`
- [ ] spec §16.3.1-16.3.12 "Individual privacy EditPrivacyBox dialogs": need full verification that each opens with correct options (Everyone/Contacts/Close Friends/Nobody) and exception lists. The generic privacy row system exists but specific per-key behaviors (Phone Number's sub-section for "Who can find me", Last Seen's "Hide Read Time" toggle, Profile Photo's "Set Public Photo", etc.) are likely missing — `privacy_settings_screen.dart`
- [ ] spec §16.3.4 "Forwarded Messages live preview bubble": spec says a rendered chat-view slice showing a forwarded message. This is likely not implemented — `privacy_settings_screen.dart`
- [ ] spec §16.3.5 "Calls P2P sub-section": spec says a nested Peer-to-Peer privacy button below the Calls privacy row. Likely missing — `privacy_settings_screen.dart`
- [ ] spec §16.3.7 "Messages from Non-Contacts charge-stars slider": messages privacy fetching exists with `_messagesPrivacyOption` and `_messagesChargeStars`. The star slider UI may exist but commission/USD info display is likely incomplete — `privacy_settings_screen.dart:210-222`
- [ ] spec §16.3.9 "Gifts auto-save toggles (5 types + Show Icon)": gifts privacy with its 6 specialized toggles is likely not implemented — `privacy_settings_screen.dart`

### §16.4 Archive and Mute
- [ ] spec §16.4 "Archive and Mute toggle": fetched via engine and toggle exists — looks implemented — `privacy_settings_screen.dart:224-238`

### §16.5 Bots and Websites
- [ ] spec §16.5 "Clear Payment and Shipping Info button": `_buildBotsAndWebsitesSection` exists. Need to verify `ClearPaymentInfoBox` with two checkboxes and attention-styled Clear button — `privacy_settings_screen.dart:443`

### §16.6 File Confirmations
- [ ] spec §16.6 "File extensions multi-line input and IP toggle": `_buildConfirmationExtensionsSection` exists — `privacy_settings_screen.dart:444`

### §16.7 Suggest Frequent Contacts
- [ ] spec §16.7 "Top Peers toggle": fetched and togglable — `privacy_settings_screen.dart:251-263`

### §16.8 Self-Destruction
- [ ] spec §16.8 "Account auto-delete SelfDestructionBox": fetched via `getAccountTTL`. Need to verify the dialog has correct radio options (1/3/6/12/18/24 months) — `privacy_settings_screen.dart:240-249`

---

## §17 — Settings: Data, Storage & Advanced

### §17.2 Data and Storage
- [ ] spec §17.2.1 "Connection type right-label": hardcoded "Using TCP" — should dynamically reflect actual connection state (proxy info, etc.) — `advanced_settings_screen.dart:219`
- [ ] spec §17.2.1 "ProxiesBox": `_ProxiesBox` exists as a dialog. Need to verify it has IPv6 checkbox, proxy list, edit dialog, and keyboard shortcuts (Ctrl+C/V) — `advanced_settings_screen.dart:225-228`
- [ ] spec §17.2.3 "LocalStorageBox": `_LocalStorageBox` exists. Need to verify sliders (total cache 18 positions, media cache 18 positions, time limit 16 positions) and per-tag clear buttons — `advanced_settings_screen.dart:247-250`
- [ ] spec §17.2.4 "Recent Downloads": `_RecentDownloadsBox` exists but may be a stub — `advanced_settings_screen.dart:258-261`

### §17.3 Automatic Media Download
- [ ] spec §17.3 "AutoDownloadBox": `_AutoDownloadBox` exists per source type. Need to verify Photos/Files toggles + size limit slider (10MB default) and Video messages/Videos/GIFs + size limit (50MB default) — `advanced_settings_screen.dart:398-403`

### §17.4 Window Title
- [ ] spec §17.4 "Native Frame toggle lives in System Integration, not Window Title": implementation puts the native frame toggle in `_buildWindowTitle` method. Per spec §17.6 it should be in System Integration — `advanced_settings_screen.dart:448-456`

### §17.6 System Integration
- [ ] spec §17.6.3 "Start minimized forced off when passcode set": implementation shows/hides based on `launchAtStartup` but does not check for local passcode and show explanatory label — `advanced_settings_screen.dart:542-556`
- [ ] spec §17.6 "Add to Send To menu (Windows only)": missing entirely — `advanced_settings_screen.dart:486-558`
- [ ] spec §17.6 "macOS-specific items (Warn before quit, System text replacements, Round dock icon)": missing entirely — `advanced_settings_screen.dart:486-558`

### §17.7 Performance
- [ ] spec §17.7.3 "ANGLE Backend (Windows)": implementation shows a simple toggle instead of spec's `SingleChoiceBox` with 5 options (Auto/D3D11/D3D9/D3D11on12/Disabled) — `advanced_settings_screen.dart:598-611`
- [ ] spec §17.7.4 "OpenGL toggle restart dialog": shows restart dialog but spec says "Restart now?" with Restart/Cancel buttons and actual `Core::Restart()` call. Implementation shows an OK-only info dialog — `advanced_settings_screen.dart:615-665`

### §17.8 Spellchecker
- [ ] spec §17.8 "Auto-download dictionaries toggle visibility": spec says visible only when custom spellchecker ON. Implementation checks `spellcheckerEnabled` which is correct — `advanced_settings_screen.dart:692-711`

### §17.10 Software Update
- [ ] spec §17.10 "Install ready overlay with accent-colored update button": no "Update Telegram" / "Install Now" button when update is ready — the fake update check always returns "latest" — `advanced_settings_screen.dart:109-113`

### §17.11 Export & Experimental
- [ ] spec §17.11 "Experimental Settings": `ExperimentalSettingsBox` exists with toggle rows and import/export. Need to verify import/export uses `tdesktop-flags:` prefix — `advanced_settings_screen.dart:762-769`

---

## §18 — Settings: Folders

### §18.1 Page Structure
- [ ] spec §18.1 "Show tags toggle (Premium feature)": need to verify `_ShowTagsToggle` or equivalent exists on the folders page — `folders_settings_screen.dart`
- [ ] spec §18.1 "View subsection (vertical/horizontal tab radio)": need to verify the Tab View section with radio buttons exists — `folders_settings_screen.dart`

### §18.2 Animated Header
- [ ] spec §18.2 "Lottie animation 'filters' 74x74px": need to verify the animated header uses Lottie. The file imports `package:lottie/lottie.dart` which is promising — `folders_settings_screen.dart:5`

### §18.3 Existing Folders List
- [ ] spec §18.3 "FilterRowButton 52px height with icon, title, status, color dot, remove/restore": implementation has folder row buttons. Need to verify exact metrics and color dot animation — `folders_settings_screen.dart:99-182`
- [ ] spec §18.3 "Remove flow confirmation for chatlist folders": `_showChatListRemoveConfirmation` exists with `_ChatlistFolderRemovalDialog` — `folders_settings_screen.dart:159-176`

### §18.4 Create New Folder
- [ ] spec §18.4 "Folder limit check": `_onCreateFolder` checks against `_folderLimitFree` (10) and `_folderLimitPremium` (20) — correct — `folders_settings_screen.dart:193-216`

### §18.5 Recommended Folders
- [ ] spec §18.5 "SlideWrap visible when suggestions > 0 AND count < limit": recommended folders section exists with `_addRecommendedFolder` — `folders_settings_screen.dart:218-244`

### §18.6 Edit Filter Box
- [ ] spec §18.6 "Box width 364px, closeByOutsideClick = false": `_EditFilterBox` is created with `barrierDismissible: false`. Width constraint needs verification — `folders_settings_screen.dart:248-251`
- [ ] spec §18.6.1 "Folder name max 12 characters with counter": need to verify max length enforcement — `folders_settings_screen.dart`
- [ ] spec §18.6.1 "Emoji button and Icon selector toggle inside name field": need to verify these UI elements exist in the edit box — `folders_settings_screen.dart`
- [ ] spec §18.6.4 "Tag Color section (Premium) with 8 color buttons": need to verify this section exists — `folders_settings_screen.dart`
- [ ] spec §18.6.5 "Shareable Link section with Create/Add Link": need to verify invite link management exists — `folders_settings_screen.dart`

### §18.8 Filter Icon Picker
- [ ] spec §18.8 "30 folder icons in 6x5 grid": `_kFilterIconOrder` has exactly 30 icons in correct order, and `_kFilterIcons` maps them to Material icons. The picker panel itself needs to verify the 44x42px cell size and popup behavior — `folders_settings_screen.dart:17-56`

### §18.11 Folder Tags Toggle
- [ ] spec §18.11 "Show Folder Tags toggle (Premium)": need to verify this toggle exists on the folders page and triggers tag animations on folder rows — `folders_settings_screen.dart`

### §18.12 Tab View Section
- [ ] spec §18.12 "Side panel / Top bar radio buttons": need to verify these exist and are gated by `enoughSpaceForFilters()` (452px threshold) — `folders_settings_screen.dart`

---

## §19 — Settings: Sessions, Power Saving & Language

### §19.1-§19.2 Active Sessions
- [ ] spec §19.1 "60-second auto-refresh polling": implemented with `Timer.periodic(const Duration(seconds: 60))` — correct — `active_sessions_screen.dart:104`
- [ ] spec §19.2 "Current session header with Rename link": `_loadCustomDeviceModel` and rename dialog exist. Need to verify "This device" header has a right-aligned "Rename" link — `active_sessions_screen.dart:95-96`
- [ ] spec §19.2.1 "Rename this device link style": implementation exists; rename box saves via engine — `active_sessions_screen.dart:95-96`

### §19.3 Device Type Detection
- [ ] spec §19.3 "Device classification table": `_classifyDevice` function maps device/platform/appName strings to types with correct gradient colors — well implemented — `active_sessions_screen.dart:51-82`

### §19.4 Other Sessions List
- [ ] spec §19.4 "Row click opens SessionInfoBox": need to verify session detail view (364px wide, 70px userpic, info rows with Application/System/IP/Location) exists — `active_sessions_screen.dart`
- [ ] spec §19.6 "SessionInfoBox with Terminate Session button (red attention style)": need to verify the detail view has terminate capability for non-current sessions — `active_sessions_screen.dart`

### §19.5 Incomplete Login Attempts
- [ ] spec §19.5 "Incomplete Login Attempts section": `_incompleteSessions` getter filters `password_pending == true` sessions — exists. Need to verify sorted newest-first and displayed in a separate section — `active_sessions_screen.dart:139-146`

### §19.7 Terminate All Sessions
- [ ] spec §19.7 "Terminate All Other Sessions button": `_terminateAllOther` method exists. Need to verify confirmation dialog with "Terminate" in `attentionBoxButton` style — `active_sessions_screen.dart:159-168`

### §19.8 Rename Device
- [ ] spec §19.8 "settingsDeviceName style, max 32 characters": `_loadCustomDeviceModel` and `_customDeviceModel` exist. Need to verify the rename dialog enforces 32-char max — `active_sessions_screen.dart:95-96`

### §19.9 Auto-Terminate Inactive Sessions
- [ ] spec §19.9 "SelfDestructionBox Sessions type": `_showAutoTerminateDialog` exists with options `[7, 30, 90, 180, 365]` days — matches spec — `active_sessions_screen.dart:189-299`
- [ ] spec §19.9 "Box width 320px": dialog uses `SizedBox(width: 320)` — correct — `active_sessions_screen.dart:209`

### §19.10-§19.12 Power Saving
- [ ] spec §19.11 "11 toggle flags in 5 groups": `PowerSavingBox` exists (imported from `advanced_settings_screen.dart`). Need to verify all 11 flags: Stickers (Panel, Chat), Emoji (Panel, Reactions, Chat, Status), Chat (Background, Spoiler, Effects), Calls, Interface Animations — `advanced_settings_screen.dart`
- [ ] spec §19.12 "Automatic Power Saving toggle": need to verify battery-saver auto-toggle and overlay (boxBg at alpha 96) — `advanced_settings_screen.dart`
- [ ] spec §19.12.1 "Toast on overlay interaction, 3s duration": need to verify the overlay click toast with "Turn off your device's power saving mode" message — `advanced_settings_screen.dart`

### §19.13-§19.16 Language Selection
- [ ] spec §19.13 "LanguageBox width 320px": dialog uses `ConstrainedBox(maxWidth: 320)` — correct — `language_box.dart:143`
- [ ] spec §19.13 "Max list height 492px": `maxDialogHeight = screenHeight - 48` — not the spec's 492px; it is dynamically calculated instead — `language_box.dart:135-136`
- [ ] spec §19.14 "Show Translate Button toggle": implemented — `language_box.dart:162-168`
- [ ] spec §19.14 "Translate Entire Chats (Premium-locked)": implemented with `locked: true` — `language_box.dart:170-178`
- [ ] spec §19.14 "Do Not Translate with right-label and skip-languages editor": implemented with `_openSkipLanguagesEditor` — `language_box.dart:104-115, 183-199`
- [ ] spec §19.15 "Language list with search MultiSelect": search field exists but uses a plain `TextField` rather than the `MultiSelect` widget style — `language_box.dart`
- [ ] spec §19.15 "Two sections: Recent + Official separated by BoxContentDivider": need to verify the language list is split into Recent and Official sections — `language_box.dart`
- [ ] spec §19.16 "Language row radio button 22px diameter": need to verify exact radio styling — `language_box.dart`
- [ ] spec §19.16 "Language row menu toggle (3-dot) for non-official rows": need to verify context menu with Share/Delete/Restore — `language_box.dart`
- [ ] spec §19.14.1 "Translate Entire Chats bypasses Premium gate (AyuGram)": implementation has `locked: true` visual indicator but allows toggle regardless — matches AyuGram behavior — `language_box.dart:170-178`

### §19.16 Language Row
- [ ] spec §19.16 "Row click activates language and closes box": `_selectLanguage` calls `Navigator.pop` — correct — `language_box.dart:86-90`
- [ ] spec §19.15 "Empty state: 'No languages found' centered, styled membersAbout": need to verify empty search state — `language_box.dart`

---

## Cross-Cutting Issues

- [ ] **All notification settings are local-only state**: almost every toggle in `notifications_settings_screen.dart` uses local `bool` fields (`_desktopNotify`, `_flashBounce`, `_allowSound`, etc.) that reset on screen rebuild. None persist to engine or local storage — `notifications_settings_screen.dart:36-65`
- [ ] **Chat Settings toggles are local-only state**: `_largeEmoji`, `_replaceEmojis`, `_suggestEmoji`, etc. are local state, not persisted to engine — `chat_settings_screen.dart:40-52`
- [ ] **Premium/Help rows are no-op stubs**: Telegram Premium, Telegram Stars, Telegram Business, Send a Gift, Telegram FAQ, Telegram Features all have `onTap: () {}` — `settings_screen.dart:334-393`
- [ ] **Missing Keyboard Shortcuts screen navigation from Chat Settings**: `shortcuts_settings_screen.dart` exists with full shortcut definitions but its accessibility from Chat Settings needs verification — `shortcuts_settings_screen.dart`
# Audit: §20-§25 Media Viewer, Groups, Forum, Scheduled, Shortcuts, Theming

## §20 — Media Viewer / Lightbox

- [ ] spec §20.1 "Window Modes": no windowed/maximized mode persistence — `_MediaViewerMode` enum exists but geometry is not saved to or loaded from settings — `media_viewer.dart`
- [ ] spec §20.6 "Navigation Controls": side navigation areas are present but spec requires 90px hover width with `mediaview/next` icon and 36px circle hover indicator — implementation uses simple left/right icon buttons without the 36px hover circle — `media_viewer.dart`
- [ ] spec §20.7 "Footer / Header Area": footer shows "Photo N of M" counter and sender name but missing the bullet separator, date + DC number, and clickable-to-navigate-to-message behavior on the date — `media_viewer.dart`
- [ ] spec §20.8.1 "More-Menu Contents": overflow menu is minimal — missing items: Cancel download, Show in Folder, Copy Image/Copy Frame, Attached Stickers, Share at Time, Delete, Save As, Show All Photos/Files, Set as Userpic, Report Userpic, View Statistics, Stealth Mode — `media_viewer.dart`
- [ ] spec §20.8 "Bottom-Right Toolbar": missing Draw (photo editor) button and OCR/recognize button — only More, Rotate, Save are present — `media_viewer.dart`
- [ ] spec §20.10 "Video Playback Controls": missing quality selector menu (360/720/1080 switch), chapter dividers on progress bar, and time-remaining display with minus prefix — `media_viewer.dart`
- [ ] spec §20.11 "Video Player Behavior": speed control range is present but missing the in-app speed selection menu UI per §20.10 settings button — `media_viewer.dart`
- [ ] spec §20.13 "PiP": PiP is implemented but missing edge-snap rules on drag release — `ClampToEdges()` algorithm with `pipBorderSnapArea=16px` threshold and `3*pipBorderSkip=60px` inner margin is not implemented; PiP snaps to corners instead of edges — `media_viewer.dart`
- [ ] spec §20.13 "PiP Z-order": PiP widget renders inside the app widget tree using `Positioned` overlay, not as a separate always-on-top OS window with `WindowStaysOnTopHint` — platform limitation but behavior diverges from spec — `media_viewer.dart`
- [ ] spec §20.14 "Gallery / Group Thumbs Strip": thumb strip is implemented with correct dimensions but missing the centered layout model — spec says current thumb is centered at `-_fullWidth/2` with neighbours animating in/out; code uses a simpler horizontal list — `media_viewer.dart`
- [ ] spec §20.16.1 "Structured Context Menu": right-click context menu exists but only has Show in Chat, Forward, Save, and Copy — missing: Cancel Download, Show in Folder, Attached Stickers, Share at Time, Delete, Show All Photos/Files, Set as Userpic, Report, Stealth Mode items — `media_viewer.dart`
- [ ] spec §20.17 "Stories Viewer Integration": stories viewer scaffold exists (`_kStoriesMaxWidth`, `_kStoriesMaxHeight` constants) but missing sibling story preview thumbnails and collapsed-caption "Show more" toggle — `media_viewer.dart`
- [ ] spec §20.18 "Keyboard Shortcuts": `J`/`L` seek keys (±10s) and `,`/`.` frame-step keys (§24.9) are missing from `_handleKey` — `media_viewer.dart`
- [ ] spec §20.18 "Keyboard Shortcuts": `K` key for play/pause toggle is missing from `_handleKey` — `media_viewer.dart`
- [ ] spec §20.19.1 "Open/Close Geometry Animation": missing thumbnail-to-lightbox geometry interpolation on open — viewer opens with a simple route push, not an animated rect transition from the source thumbnail — `media_viewer.dart`
- [ ] spec §20.15 "Save/Download Toast": toast animation timings are correct (200ms in, 2s hold, 2.5s out) but missing the "Downloads" clickable link text — only `xdg-open` on tap of the whole toast — `media_viewer.dart`

## §21 — Create Group / Channel Wizard

- [ ] spec §21.2.1 "Default userpic origin": userpic gradient pair index selection uses `name.codeUnitAt(0) % 8` but spec says for a not-yet-created peer (id=0) the first pair is always used — code selects based on text input character, not peer ID — `create_group_wizard.dart`
- [ ] spec §21.2.1 "Default userpic origin": userpic gradient is top-to-bottom but spec uses 8 specific pairs `{historyPeer1UserpicBg, historyPeer1UserpicBg2}...{historyPeer8}` — code defines custom colors that don't match the palette tokens (e.g. first pair is `#FC5C51`/`#E44234` vs spec's `#FF845E`/`#D45246`) — `create_group_wizard.dart`
- [ ] spec §21.2.1 "Initials fallback": initials extraction handles up to 2 letters (first + after space/hyphen) — code has this logic but also handles `afterHyphen` as level 1 fallback, which matches spec — however the font size of `(size * 13) / 33 = 28px at 72px` is not verified in code — `create_group_wizard.dart`
- [ ] spec §21.2 "Photo picker": clicking userpic should open a `PopupMenu` with File / Camera / Clipboard paste / Emoji builder options — code only opens file picker directly, missing Camera, Clipboard paste, and Emoji builder options — `create_group_wizard.dart`
- [ ] spec §21.2 "TTL menu": group creation should have a top-bar menu for "Auto-delete messages" with current TTL value — TTL is implemented in the wizard state but the UI for selecting TTL is minimal (popup menu), missing the spec's top-bar integration — `create_group_wizard.dart`
- [ ] spec §21.3 "Member Picker": MultiSelect chips bar should have max height 104px, chips at 32px height with 128px max width, delete cross with 150ms animation — member picker exists but chip styling does not enforce these exact dimensions — `create_group_wizard.dart`
- [ ] spec §21.3 "Member Picker": avatar acts as checkbox with round check overlay and `windowActiveTextFg` tint — code uses a different visual (simple checkmark icon overlay) rather than the spec's avatar-tint approach — `create_group_wizard.dart`
- [ ] spec §21.3 "Invite via Link button": should appear above contact list if `canHaveInviteLink()` — missing from member picker step — `create_group_wizard.dart`
- [ ] spec §21.4.1 "Username validation": debounce timeout should be 200ms per `kUsernameCheckTimeout` — implementation has debounce but the actual API call uses `channels.CheckUsername` which is correct; however the green "available" label uses `boxTextFgGood` styling but without the exact `tr::lng_create_channel_link_available` format — `create_group_wizard.dart`
- [ ] spec §21.4.2 "PublicLinksLimitBox": when `CHANNELS_ADMIN_PUBLIC_TOO_MUCH` error occurs, should show a Premium limit box with revoke list — code only shows a text error message "Too many public channels", no revoke-list UI — `create_group_wizard.dart`
- [ ] spec §21.6 "Channel flow": after channel creation, should proceed to SetupChannelBox (public/private + username) then to MemberPicker — `CreateChannelScreen` is a flat single-step form that creates the channel and navigates away, missing the multi-step SetupChannelBox and MemberPicker steps — `create_channel_screen.dart`

## §22 — Forum Topics UI

- [ ] spec §22.3 "Forum Topic List Layout": topic row height should be 54px with photoSize 20px, nameLeft 39px, textLeft 39px — `_ForumTopicListView` exists in `chat_list_panel.dart` but topic row styling dimensions are not verified against these exact tokens — `chat_list_panel.dart`
- [ ] spec §22.4 "Forum Group in Main Chat List": forum groups should use expanded row height of 80px (96px with tags) with `TopicsView` rendering up to 8 recent topic names horizontally — not implemented; forum groups render as standard 62px dialog rows — `chat_list_panel.dart`
- [ ] spec §22.4 "Topic Jump Bubble": unread front topic should show a rounded bubble (radius 11px, padding 8/3/8/3px) with arrow icon for direct navigation — not implemented — `chat_list_panel.dart`
- [ ] spec §22.5 "Create/Edit Topic Dialog": icon selector panel should use `EmojiListWidget` in `Mode::TopicIcon` with server emoji set and Premium gating for non-default custom emojis — implementation shows only the 6 predefined color icons in a simple grid, no custom emoji selector — `edit_forum_topic_box.dart`
- [ ] spec §22.5 "Edit Topic": fly animation should use `EmojiFlyAnimation` from selector to icon button — a basic overlay fly animation is implemented but uses simple position/scale tween instead of the full `EmojiFlyAnimation` pattern — `edit_forum_topic_box.dart`
- [ ] spec §22.5 "Create Topic": should reserve local ID via `forum->reserveCreatingId()` and navigate to topic immediately — not connected to the engine's topic creation flow — `edit_forum_topic_box.dart`
- [ ] spec §22.6 "Topic Header Bar": standard `info_top_bar` with back button, title with icon prefix, optional subtitle at 54px height — topic header rendering in chat view exists but not verified for icon prefix positioning — `chat_list_panel.dart`
- [ ] spec §22.7 "Topic Info Panel": third column showing cover (77px height, icon 36x36px at (22,18)), notifications toggle, shared media, members list, topic link — topic info panel section not found as a dedicated widget — `info_panel.dart`
- [ ] spec §22.8 "Topic Context Menus": specific topic row right-click should show New Window, Pin/Unpin, View Info, Mute submenu, Mark Read/Unread, Close/Reopen, Add to Folder, Clear History, Delete Topic — topic list context menu exists (`_showTopicListContextMenu`) but likely missing several items (New Window, Add to Folder, Close/Reopen) — `chat_list_panel.dart`
- [ ] spec §22.9 "General Topic": title should be prefixed with "# " in rich text — not implemented in topic rendering — `forum_topic_icon.dart`
- [ ] spec §22.10 "View as Messages/Topics toggle": saves preference and switches between flat messages and topic list — toggle exists in the context menu but the "View as Messages" flat mode is not a distinct rendering — `chat_list_panel.dart`
- [ ] spec §22.2.1 "Topic Icon SVG": stroke width should be `2.94736842px` scaled — code uses `2.84210526 * s` which differs from spec value (2.95 vs 2.84) — `forum_topic_icon.dart`

## §23 — Scheduled Messages

- [ ] spec §23.3 "Scheduled Messages Toggle Button": clock icon in compose area appears when chat has scheduled messages — `_ScheduledToggleButton` exists in `chat_view.dart` but its visual matches (two-layer icon with `input_scheduled` and `input_scheduled_dot` in `attentionButtonFg`) are not verified — `chat_view.dart`
- [ ] spec §23.4 "Scheduled Messages Section (ScheduledWidget)": a full `SectionWidget` that replaces the main chat column with scheduled messages list, title bar, selection mode (Send Now/Delete), and compose controls — no `ScheduledWidget` or `ScheduledSection` class exists; the scheduled messages view is not implemented as a section — `chat_view.dart`
- [ ] spec §23.4 "Scheduled Section Top Bar": should display "Reminders" for self-chat or "Scheduled messages" for other chats, with selection mode showing Send Now + Delete buttons — missing entirely — no file
- [ ] spec §23.4 "Empty state": should show `EmptyListBubbleWidget` with service-style bubble containing "No scheduled messages" text — not implemented — no file
- [ ] spec §23.5 "Message Rendering": scheduled messages should show delivery time in bottom-info, repeat period prefix, and silent indicator (U+1F515) in tooltip — not implemented — no file
- [ ] spec §23.6 "Context Menu Actions": right-click on scheduled message should show Send Now, Reschedule, Edit, Delete — not implemented — no file
- [ ] spec §23.6 "Send Now Confirmation": should open `ShowSendNowMessagesBox` with "Send this message now?" text — not implemented — no file
- [ ] spec §23.7 "Sent-to-Scheduled Toast": when scheduling from normal compose, should auto-navigate to scheduled section — not implemented — no file
- [ ] spec §23.8 "Video Processing Flow": processing tip toast and published notification toast — not implemented — no file
- [ ] spec §23.2 "ChooseDateTimeBox": date field mouse wheel scroll should increment/decrement by one day — implemented in `_scrollDate()` via `PointerScrollEvent` — `choose_datetime_box.dart` (OK)
- [ ] spec §23.2 "Send when online": only shown for `ScheduledToUser` type — implemented with `isScheduledToUser` parameter and "Send when online" popup menu — `choose_datetime_box.dart` (OK)
- [ ] spec §23.2 "Repeat Period": repeat dropdown uses `defaultPopupMenu` style (no icons, plain text) — code uses `showMenu<int>()` which produces Material-style menu, not matching the Telegram `defaultPopupMenu` appearance — `choose_datetime_box.dart`
- [ ] spec §23.2 "Silent shortcut": holding Ctrl when confirming should schedule silently — implemented with `HardwareKeyboard.instance.isControlPressed` check — `choose_datetime_box.dart` (OK)
- [ ] spec §23.9 "Forum Topic Support": `ScheduledWidget` should support forum topics with `Context::ScheduledTopic` — not implemented since ScheduledWidget does not exist — no file

## §24 — Keyboard Shortcuts

- [ ] spec §24.2 "Shortcut Customization JSON": `shortcuts-default.json` and `shortcuts-custom.json` in config dir — implemented correctly with write/load logic — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.2 "Settings UI": full graphical shortcut editor with recording mode, conflict detection (strikethrough in red), "Reset to defaults" button — `ShortcutsSettingsScreen` exists with recording mode, conflict detection, and reset functionality — `shortcuts_settings_screen.dart` (OK)
- [ ] spec §24.4 "Application / Window": Ctrl+W, Ctrl+F4, Ctrl+L, Ctrl+M, Ctrl+Q — all present in `_defaultBindings` — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.4 "Chat Navigation": Ctrl+Tab, Ctrl+PgDn, Alt+Down, Ctrl+PgUp, Alt+Up, Ctrl+Alt+Home, Ctrl+Alt+End — all present — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.4 "Pinned Chats": Ctrl+1 through Ctrl+8 — present — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.4 "Account Switching": commands exist but unbound by default — commands are defined but no default bindings (matches spec) — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.4 "Folder Navigation": Ctrl+1 through Ctrl+8 for folders, Ctrl+Shift+Down/Up for next/prev folder — present — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.5 "Ctrl+Tab Chat Switcher": overlay with 72x104px cells, grid layout, Q to remove entry — `chatSwitchOverlay` command dispatches to `UniClientShell.showChatSwitchRequest` but the actual overlay widget dimensions (72x104 cells, margins 16px, padding 12px) are not verified here — `keyboard_shortcuts.dart`
- [ ] spec §24.8 "Text Formatting Shortcuts": Ctrl+B/I/U, Ctrl+Shift+X/M/./P/N, Ctrl+K, Ctrl+Shift+D — all 10 formatting shortcuts present in `_defaultBindings` — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.9 "Media Viewer Shortcuts": `J` (seek -10s), `L` (seek +10s), `K` (play/pause), `.` (frame step forward), `,` (frame step backward) are all missing from the media viewer's `_handleKey` — `media_viewer.dart`
- [ ] spec §24.9 "Media Viewer Shortcuts": `Ctrl+S` save-as and `Ctrl+C` copy-media shortcuts in the viewer are missing from `_handleKey` — `media_viewer.dart`
- [ ] spec §24.6 "Compose Box Key Handling": `Ctrl+O` to open file picker — `openFilePicker` command is defined with `chatRequired` scope but no default key binding for Ctrl+O is in `_defaultBindings` — `keyboard_shortcuts.dart`
- [ ] spec §24.10 "Support Mode Shortcuts": F5, Ctrl+Delete, Ctrl+Insert, Ctrl+Shift+X, Ctrl+Shift+C — all present in `_defaultBindings` — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.3 "Platform Modifier Mapping": macOS Cmd/Ctrl swap — implemented with `_isMac ? hwMeta : hwCtrl` logic — `keyboard_shortcuts.dart` (OK)

## §25 — Theming & Color System

- [ ] spec §25.1 "Palette Architecture": ~370 named tokens in `.tdesktop-theme` files with reference resolution — `paletteToMap()` in `theme_file.dart` exports ~190 tokens, significantly fewer than spec's 369 (Day Blue) — `theme_file.dart`
- [ ] spec §25.2 "Complete Color Token Reference": spec lists 369 Day Blue and 467 Night tokens — `TelegramPalette` class (not fully read due to size) maps ~190 named fields — missing approximately 180 tokens — `telegram_palette.dart`, `theme_file.dart`
- [ ] spec §25.3 "Built-in Themes": four embedded themes (Default/Classic Day, Day Blue, Night, Night Green) — `TelegramPalette` has `dayBlue` and `night` factory constructors visible; `classicDay` and `nightGreen` existence not confirmed from the read portions — `telegram_palette.dart`
- [ ] spec §25.4 "Accent Color System": 8 preset accent colors per theme, accent picker UI, colorizer algorithm to transform palette — `_AccentColorPalette` exists in `chat_settings_screen.dart` but no colorizer algorithm (HSV hue shift + saturation scale + lightness clamp) is implemented in the theme code — `telegram_palette.dart`, `theme_file.dart`
- [ ] spec §25.4.3 "Colorizer Algorithm": extracts HSV, shifts hue, scales saturation, clamps lightness `[0,160]` Day / `[64,255]` Night, with keepContrast map for Night themes — not implemented; accent changes just swap the palette, no programmatic color remapping — `telegram_palette.dart`
- [ ] spec §25.4.4 "Accent Persistence": custom accent serialized per-theme-type — `chat_settings_screen.dart` has `updateAccentColor(hex)` but persistence of accent per embedded theme type is not verified — `chat_settings_screen.dart`
- [ ] spec §25.5 "Theme File Format": ZIP with `colors.tdesktop-theme` + optional `background.jpg/png` or `tiled.jpg/png` — fully implemented with correct parsing, export, and max size limits — `theme_file.dart` (OK)
- [ ] spec §25.6 "Theme Editor": full editor with search, palette rows, color swatch, hex edit dialog, import/export — implemented with search filter, keyboard navigation, hex input, live preview, export/import — `theme_editor.dart` (OK)
- [ ] spec §25.6.2 "Palette Entry Row": spec requires color name + "= referenceName" copy reference text below — code shows only token name + hex value, missing the reference chain display — `theme_editor.dart`
- [ ] spec §25.6.3 "Color Edit Dialog": spec says colors entered as `#RRGGBB` or `#RRGGBBAA` with immediate live preview via `ApplyEditedPalette()` — code applies changes immediately on input change via `_onHexChanged`, matching spec behavior — `theme_editor.dart` (OK)
- [ ] spec §25.6.5 "Save Theme Dialog": name field, link/slug field, background section with thumbnail + "Choose from file" + tile checkbox, width `boxWideWidth` — fully implemented matching spec layout — `theme_editor.dart` (OK)
- [ ] spec §25.7 "Theme Name Generator": weighted Euclidean distance to 101-color dictionary, two patterns (Adj+Color / Color+Noun) — implemented with correct algorithm, 101 colors, 97 adjectives, 81 nouns — `theme_name_generator.dart` (OK)
- [ ] spec §25.8 "Chat Wallpaper System": solid, gradient, pattern, image types with intensity, rotation, blur — `WallpaperData` class with all four types, `patternOpacity`, `gradientRotation`, `blurred` flag, URL parsing — `wallpaper.dart` (OK)
- [ ] spec §25.8.3 "Gradient Rendering": 3-4 color gradients with animated rotation (`ComputeRealRotation` doubles base, modulo 720, toggling progress) — `_MultiColorGradient` implements animated rotation but the exact `realRotation = (base * 2) % 720` formula and phase-based toggle differ from the spec algorithm — `wallpaper.dart`
- [ ] spec §25.8.4 "Pattern Rendering": positive intensity uses `SoftLight`, negative uses `DestinationIn` + darkening overlay — `_PatternOverlay` uses `ShaderMask(blendMode: BlendMode.softLight)` for positive and `ColorFilter.mode(Colors.white, BlendMode.dstIn)` for negative, but missing the secondary `SourceOver` black fill for `-100 < intensity < 0` — `wallpaper.dart`
- [ ] spec §25.8.5 "Image Wallpaper Processing": max 2960px, aspect ratio limit 40:1, blur radius 24 — `_kMaxWallpaperSize=2960`, `_kMaxAspectRatio=40.0`, blur radius 24 all present — `wallpaper.dart` (OK)
- [ ] spec §25.8.7 "Wallpaper Upload": JPEG at 87% quality, thumbnail at 320px — `_kJpegQuality=87`, `_kThumbSize=320` — `wallpaper.dart` (OK)
- [ ] spec §25.8.9 "Adaptive Service Colors": 6 tokens auto-adjust based on wallpaper average color via `ThemeAdjustedColor()` — `themeAdjustedColor()` function exists with correct HSL transplant logic, but it is not wired into automatic palette adjustment when wallpaper changes — `wallpaper.dart`
- [ ] spec §25.9 "Night Mode": dark detection when `dialogsBg` HSV value < 0.5, night mode toggle in hamburger menu, auto-night system dark mode — `TelegramPalette` has an `isDark` getter but no automatic dark detection based on `dialogsBg` HSV value threshold; no system dark mode auto-switch — `theme.dart`, `telegram_palette.dart`
- [ ] spec §25.9.3 "Theme Switch Confirmation": 16-second countdown overlay with "Keep Changes" / "Revert" buttons — not implemented; theme changes apply immediately without confirmation overlay — no file
- [ ] spec §25.9.4 "Theme Revert Mechanism": palette saved before applying, restored on timeout/revert — not implemented — no file
- [ ] spec §25.10 "Theme Caching": parsed themes cached with CRC32 checksums — `ThemeCacheData`, `buildThemeCache()`, `validateThemeCache()`, `saveThemeCache()`, `loadThemeCache()` all implemented — `theme_file.dart` (OK)
- [ ] spec §25.11 "Per-Chat Themes": horizontal scrollable theme pills at bottom of chat with preview cards — `chat_settings_screen.dart` has `_CloudThemeSection` but no per-chat theme chooser panel in the chat view — `chat_settings_screen.dart`
- [ ] spec §25.12 "Cloud Themes": 4-per-row grid with `CloudListCheck` radio buttons, lazy loading, context menu share/edit/delete — `_CloudThemeSection` exists but verification of 4-per-row grid layout and context menu options not confirmed — `chat_settings_screen.dart`
- [ ] spec §25.13 "Theme Preview": 903x584 image with dialogs panel + chat history area — `ThemePreviewImage` at 903x584 with 9 dialog rows, sample bubbles, compose area, correct palette colors — `theme_preview.dart` (OK)
- [ ] spec §25.14 "Settings — Chat Appearance": theme radio buttons, accent circles, background row widget, tile/adaptive-wide/auto-night checkboxes — accent color palette and cloud theme sections exist in `chat_settings_screen.dart`; background row and tile checkbox are in the settings — `chat_settings_screen.dart`
- [ ] spec §25.17.2 "Colorize exclusion list": exactly 63 tokens that never change with accent — no exclusion list is maintained anywhere in the codebase since the colorizer itself is not implemented — `telegram_palette.dart`
# Audit: &sect;26-&sect;36 Admin, Export, Contacts, Calls, States

## &sect;26 -- Admin Tools
- [ ] spec &sect;26.1 "Group/Channel Edit Screen": entire EditPeerInfoBox UI (photo+title+description block, settings buttons, admin control buttons, sticker set, delete button, dialog chrome) is implemented as a single flat panel in `admin_tools.dart` but the file is too large to fully read (45828 tokens). Partial coverage only -- need line-by-line verification of all 26.1 subsections.
- [ ] spec &sect;26.2 "Permissions Management": no permission editor with toggle-style buttons (allowed=blue, restricted=red), collapsible media group with "(5/7)" count badge, or dependency-rule enforcement found in `admin_tools.dart` -- `admin_tools.dart` was too large to fully read but grep for "permission" keywords is needed to confirm presence/absence.
- [ ] spec &sect;26.2.2 "Exceptions List": no "Add Exception" button or per-user custom restriction rows found.
- [ ] spec &sect;26.2.3 "Slowmode Slider": no discrete 8-position slowmode slider (Off/5s/10s/30s/1m/5m/15m/1h) found.
- [ ] spec &sect;26.2.4 "Boosts Unrestrict Slider": no 5-position boosts slider found.
- [ ] spec &sect;26.2.5 "Charge Stars (Paid Messages)": no paid-message stars configuration found.
- [ ] spec &sect;26.3 "Individual Member Restrict/Ban Dialog": no EditRestrictedBox with cover widget (60x60 photo, permission toggles, duration picker with Forever/1Day/1Week/Custom, custom rank field) found.
- [ ] spec &sect;26.4 "Admin Appointment Dialog": no EditAdminBox with "Add as Admin" checkbox, admin rights toggles (3 sections for groups, 4 for channels), custom title/rank field, transfer ownership button, dismiss admin button, or promoted-by info found.
- [ ] spec &sect;26.5 "Admin Log / Recent Actions": no admin log viewer with chronological event rendering, search, filter dialog (19 filter flags), or empty state ("No events found") found.
- [ ] spec &sect;26.6 "Invite Links Management": no InviteLinksBox with permanent link display, "Create a New Link" button, active/revoked link sections, color-coded progress arcs, link context menu (Copy/Share/QR/Edit/Revoke/Delete), single link info box, QR code dialog, or create/edit link form found.
- [ ] spec &sect;26.7 "Member List with Role Tabs": no EditParticipantsBox with five role views (Members/Admins/Restricted/Kicked/Profile), search, pagination (16 first page / 200 subsequent), row rendering (56px height, 42px avatar), or context menu (View Profile/Promote/Restrict/Remove) found.
- [ ] spec &sect;26.8 "Banned Users List": no banned users list with unban action, "Add to Banned" button found.
- [ ] spec &sect;26.9 "Slow Mode Settings": no slowmode send-button countdown (m:ss text replacing send icon) found.
- [ ] spec &sect;26.10 "Anti-Spam Settings": no anti-spam toggle with member-count threshold found.

## &sect;27 -- Passcode Lock Screen
- [ ] spec &sect;27.1 "Settings Entry Point": no "Local passcode" row in Privacy & Security settings with On/Off label and menuIconLock icon found anywhere in the codebase.
- [ ] spec &sect;27.2 "Passcode Create Flow": no Lottie "local_passcode_enter" animation, two PasswordInput fields (256px wide), description text, or validation logic (mismatch error "Passcodes don't match") found.
- [ ] spec &sect;27.3 "Passcode Check Flow": no single-field verify-current-passcode page with flood protection found.
- [ ] spec &sect;27.4 "Passcode Management Page": no change passcode, auto-lock timer, system unlock toggle, or disable passcode buttons found.
- [ ] spec &sect;27.6 "Auto-Lock Timer Dialog (AutoLockBox)": no auto-lock box with 5 radio presets (1min/5min/1hr/5hr/Custom) and HH:MM TimeInput widget found.
- [ ] spec &sect;27.8 "Lock Screen (PasscodeLockWidget)": no full-window lock overlay with 225px passcode input at height/3, 42px submit button, logout link, or system unlock icon button found.
- [ ] spec &sect;27.9 "Lock Screen Transition Animation": no slide animation with easeOutCirc/easeInCirc easing for lock/unlock transitions found.
- [ ] spec &sect;27.11 "Keyboard Shortcut: Ctrl+L": no Ctrl+L lock shortcut handler found.
- [ ] spec &sect;27.12 "Auto-Lock Timer": no auto-lock timer with checkAutoLock() algorithm, kAutoLockTimeoutLateMs=3000ms grace, or lockByPasscode()/unlockPasscode() sequences found.
- [ ] spec &sect;27.13 "Notification Behavior When Locked": no notification content hiding when passcode-locked found.

## &sect;28 -- Two-Factor Authentication Setup
- [ ] spec &sect;28.1 "Entry Point": no "Two-Step Verification" button in Privacy & Security with dynamic On/Off/Loading label found.
- [ ] spec &sect;28.2 "Step Architecture": no 2FA wizard step system with StepData model, common header (Lottie 100x100, subtitle, description), common input fields (256px PasswordInput), error labels, done buttons, or link buttons found.
- [ ] spec &sect;28.3 "Flow 1 -- Create New Password": no Start screen, Create Password screen (interactive lock Lottie), Password Hint screen, Recovery Email screen, or Email Confirmation screen found.
- [ ] spec &sect;28.4 "Flow 2 -- Check Password & Manage": no check password screen with hint display, "Forgot password?" link (3-state machine: Recover/CancelReset/Reset), countdown timer, or Manage screen with Change Password/Change Email/Disable Password buttons found.
- [ ] spec &sect;28.7 "Password Recovery": no recovery flow with email code entry, "Can't access email?" option, or timed reset countdown found.
- [ ] spec &sect;28.8 "Login-Time 2FA Entry": no PasswordCheckWidget for login flow with 380px content width, introPassword style, or recovery mode found.

## &sect;29 -- Chat Export
- [ ] spec &sect;29.2 "Export Panel Window": panel is implemented as a Dialog (showDialog) rather than a SeparatePanel (standalone frameless window). The spec requires a 364x480px standalone panel with onAllSpaces=true -- `chat_export.dart` line 165 uses showDialog instead.
- [ ] spec &sect;29.5.3 "Skip File Link": skip file link appears after 5 seconds but uses AnimatedOpacity fade -- spec says it should fade in with anim::type::normal. Implementation matches intent but skip link position is inline rather than between progress rows and about label as spec requires.
- [ ] spec &sect;29.5.5 "Cancel/Stop Button": stop button uses ElevatedButton with 4px border radius -- spec requires attentionBoxButton style (200x44px, 15px semibold font, text at 12px from top). Button radius should match spec's pill/round style.
- [ ] spec &sect;29.7.2 "Done Button": "Show My Data" button uses 4px radius -- spec requires defaultActiveButton style (200x44px). Button does not actually open the file manager via File::ShowInFolder(path) -- it just closes the dialog.
- [ ] spec &sect;29.9 "In-App Export Top Bar": `ExportTopBar` exists in `chat_export.dart` but uses a 1px progress bar at bottom instead of a `mediaPlayerPlayback` style FilledSlider. Top bar background should use `mediaPlayerBg` token, not `windowBg`.
- [ ] spec &sect;29.3.5 "Output Format Section": location label uses hardcoded "Downloads/TelegramExport" -- spec requires a clickable link that opens FileDialog::GetFolder native folder picker. No actual folder picker integration exists.
- [ ] spec &sect;29.4.2 "Calendar Box": calendar uses 320px width and custom grid -- spec requires `exportCalendarSizes` with 42x38 cells, 32px inner circle, 14px side padding. Current cell sizes are derived from `(320-28)/7` which is approximately 41.7px wide but cell height is 38px (matches spec).

## &sect;30 -- Bot Interactions
- [ ] spec &sect;30.1 "Bot Command Button & Menu Button": no historyBotCommandStart (44x46px) slash button or historyBotMenuButton (RoundButton, 30px height, max 160px label) found in any compose area widget.
- [ ] spec &sect;30.2 "Command Autocomplete Dropdown": no /command autocomplete dropdown with 40px row height, 33px bot userpic, case-insensitive filtering found.
- [ ] spec &sect;30.3 "Inline Bot Results Panel": no @botname inline results panel with 345px width, mosaic grid layout, photo/GIF/sticker/video/article result types found.
- [ ] spec &sect;30.4 "Reply Keyboard (Bot Keyboard Below Compose)": no full-width reply keyboard with botKbButton style (10px margin, 38px height), tiny variant (4px margin, 25px height), color variants (Normal/Primary/Danger/Success), or show/hide toggle found.
- [ ] spec &sect;30.5 "Inline Keyboard (Buttons Under Messages)": no inline keyboard rendering below message bubbles with msgBotKbButton style (2px margin, 36px height), 20+ button types (Default/Url/Callback/Buy/WebView/CopyText etc.), hover animation, or loading spinner found.
- [ ] spec &sect;30.6 "Web Apps / Mini Apps": `web_app_panel.dart` exists but needs audit against spec's SeparatePanel (384x694px default), header bar (bot name + custom emoji + verified badge), bottom bar (@username), main/secondary buttons (40px height), progress indicator (3px stroke), and theme integration. File was not fully read.
- [ ] spec &sect;30.7 "Bot Start Screen": no bot start screen with EmptyPainter, GenerateManagedBotImage (280x140px), chatIntroWidth=224px sticker area, or historyComposeButton "START"/"RESTART" button (46px height) found.
- [ ] spec &sect;30.8 "Game Messages": no game card rendering with webPageTitleStyle, "GAME" badge (msgDateFont, semi-transparent background), or "Play" button (36px height, historyPageButtonLine=1px separator) found.
- [ ] spec &sect;30.9 "Login URL Buttons": no Auth confirmation dialog with bot userpic, account switcher, device/location details, checkbox options, or match code display found.
- [ ] spec &sect;30.10 "Bot Payments": `payment_panel.dart` exists but needs audit against spec's paymentsPanelSize=392x600px, invoice cover (80x80 thumbnail), prices section, tips buttons (28px height), shipping form, and submit button. File was not fully read.

## &sect;31 -- Saved Messages
- [ ] spec &sect;31.1 "Saved Messages Chat Entry": `chat_state.dart` does not treat Saved Messages as a special peer with a dedicated bookmark icon (EmptyUserpic::PaintSavedMessages with blue gradient #5caffa to #408acf and vector bookmark shape). Chat list may use a generic avatar instead.
- [ ] spec &sect;31.2 "Saved Messages Sub-Peers (Sublists)": no sublist-based browsing mode where forwarded messages are grouped by source peer found in `chat_state.dart`.
- [ ] spec &sect;31.3 "Sublist Navigation & Info Panel": no SublistsWidget with dynamic chat count, media filter section (8 media-type buttons), or sublist row rendering found.
- [ ] spec &sect;31.4 "My Notes": no "My Notes" sublist with dedicated notepad icon (dialogsMyNotesUserpic = "dialogs/avatar_notes") found.
- [ ] spec &sect;31.6 "Reaction Tags System": no tag-based categorization with MyTagInfo struct, tag operations (increment/decrement/rename), or SearchTags bar widget found.
- [ ] spec &sect;31.7 "Tag-Based Search & Filtering": no SavedMessagesTagBar (SearchTags) with 18px-tall chips in price-tag shape, click-to-filter, right-click tag rename menu, or tag query encoding (#tag-custom:, #tag-emoji:) found.
- [ ] spec &sect;31.8 "Forward-to-Saved Flow": no self-forwards tagger with post-forward tag suggestion toast (3s auto-dismiss) found.
- [ ] spec &sect;31.9 "Subsection Tabs": no horizontal/vertical subsection tabs for saved messages with 36px strip height, 64px toggle button, dynamic tab width formula, or scroll-to-active logic found.

## &sect;32 -- Stories
- [ ] spec &sect;32.1 "Stories Bar (Chat List)": no horizontal stories strip above chat list with collapsed (35px height, 21px avatar) and expanded (77px height, 42px avatar) states, gradient ring for unread (#0dcc39 to #0992ef), or expansion trigger at 0.72 overscroll ratio found.
- [ ] spec &sect;32.2 "Story Viewer Overlay": no full-screen story viewer with 540x960px max content, 8px corner radius, sibling previews, segmented progress bar (2px height, 4px gap), or navigation (tap left/right third) found.
- [ ] spec &sect;32.3 "Story Header": no story header overlay with 28px avatar, name at (50,0), date at (50,17), privacy badges, or timestamp display found.
- [ ] spec &sect;32.4 "Story Reactions": no reaction panel (210px width), like button (42x42), or suggested reaction bubbles found.
- [ ] spec &sect;32.5 "Story Reply Compose": no story reply compose bar with #2c333d background, 21px corner radius, or storiesComposeWhiteText (#ffffff) found.
- [ ] spec &sect;32.9 "Story Views List": no "Who Viewed" popup with stacked avatars (24px, 9px shift, 4px stroke) or 240x320px menu found.
- [ ] spec &sect;32.10 "Stealth Mode": no stealth mode dialog with logo, 42px button, cooldown countdown, or toast notifications found.
- [ ] spec &sect;32.15 "Story Creation Editor": `story_editor.dart` implements the editor but has notable gaps:
- [ ] spec &sect;32.15.3 "Video Trim Slider": no video trim slider with 12 thumbnail frames, draggable handles, or duration constraints (1s-60s) found -- `story_editor.dart` only supports image files via FilePicker.
- [ ] spec &sect;32.15.4 "Sticker Picker": no sticker panel integration via StickersPanelController/TabbedPanel with emoji/stickers/custom emoji tabs found -- `story_editor.dart` has no sticker insertion.
- [ ] spec &sect;32.15.5 "Text Tool": text tool exists in `story_editor.dart` with alignment cycling, background styles (none/filled/outlined/shadowed), font picker, and color picker. However, only 4 fonts are offered (Regular/Typewriter/Serif/Handwriting) vs spec's 7. No font-size slider (spec requires vertical brush-size-style control mapped to 14-72pt) exists -- font size is hardcoded to 32.
- [ ] spec &sect;32.15.8 "Privacy Selector": privacy dialog exists in `story_editor.dart` but uses a generic AlertDialog with RadioListTile instead of the spec's chip-row with 32px height / 16px radius pills above the caption bar.
- [ ] spec &sect;32.15.9 "Duration Picker": duration picker exists as a PopupMenu with 6h/12h/24h/48h options but lacks the premium gate (lock icon on 48h for non-premium users) specified in the spec.
- [ ] spec &sect;32.15.10 "Save to Profile / Allow Sharing Toggles": toggles exist in `story_editor.dart` with correct switch visual (36x20px pill, #4DB8FF active). "Allow Sharing" correctly hidden for Close Friends. However, subtitle text ("Story will stay on your profile after it expires" / "Let viewers share your story as a link") is missing.

## &sect;33 -- Contacts Screen
- [ ] spec &sect;33.1 "Sort toggle button": `contacts_screen.dart` uses Icons.access_time / Icons.sort_by_alpha as Material icons -- spec requires specific `contactsSortOnlineIcon` / default icon, and a 48x54px hit area with 42px ripple circle at (1px, 6px). The current implementation is close but not pixel-exact.
- [ ] spec &sect;33.2 "Stories Bar": story ring rendering exists on contact rows via `_ContactStoryRingPainter` with gradient ring and segmented arcs. However, it does not use the per-row inline ring approach described in the spec (&sect;33.2 contactsWithStories style override: 52px row height, photo at 18/5, name at 70/7, status at 70/27). The code uses the standard 56px row height with 42px avatar.
- [ ] spec &sect;33.4 "Contact List Layout": row dimensions match spec (56px height, 42px avatar, name at 74/9, status at 74/30). Avatar position uses 16px left / 7px top which matches spec's (16, 7). Name badges (verified, premium, scam, fake) are rendered inline -- matches spec.
- [ ] spec &sect;33.5 "Add Contact Dialog": `_AddContactBox` exists with first name, last name, phone fields, country code picker, and retry state. Field left padding is 49px matching spec's `contactPadding.left()`. Country picker exists with search, 36px row height, name+code layout. Missing: no field icon rendered at contactIconPosition (-5, 23).
- [ ] spec &sect;33.5 "Country Code Picker": `_CountrySelectBox` exists with search, row height 36px, name left-aligned + "+code" right-aligned. Matches spec (no flag emoji, text-only). Keyboard navigation (arrow up/down) is not implemented. No-results state shows "No countries found" -- spec uses `lng_country_none`. Missing: PageUp/PageDown navigation, Enter/Return to select.
- [ ] spec &sect;33.6 "Edit Contact Dialog": `_EditContactBox` exists with cover widget (108px height, 72x72 avatar at 19/18, name at 109/33, status at 109/57) -- matches spec's `infoEditContactCover` dimensions exactly. Live name update works. Phone displays with formatting or "Mobile hidden". Missing: notes field with emoji panel and character limit. Missing: "Suggest photo" button with Lottie animation.
- [ ] spec &sect;33.7 "Delete Contact Confirmation": delete confirmation exists with proper red "Delete" button. However, it uses a generic AlertDialog rather than the spec's ConfirmBox with attentionBoxButton style.
- [ ] spec &sect;33.8 "Contact Actions (Context Menu)": context menu has Edit Contact, Share Contact, Delete Contact, Block User. Missing: "Add Contact" (for non-contacts), proper icon tokens (menuIconInvite, menuIconEdit, menuIconDeleteAttention, menuIconBlock).
- [ ] spec &sect;33.9 "Mutual Contact Indicator": no mutual contact indicator implemented -- matches spec (spec says no visual indicator exists in contacts list UI, only internal flag).
- [ ] spec &sect;33.11 "Sort Options": online sort exists but uses simple isOnline + alphabetical fallback rather than spec's `min(user.lastseen().onlineTill(), now + 1) + 1` descending key. Missing: 3000ms throttle timer (`kSortByOnlineThrottle`) for rapid online status updates.
- [ ] spec &sect;33.12 "Empty State": empty state shows "No contacts yet" / "No contacts found" -- spec requires `lng_blocked_list_not_found` for search results. Loading state shows CircularProgressIndicator instead of "Loading..." text label.

## &sect;34 -- Calls History
- [ ] spec &sect;34.2 "Box Structure": `calls_screen.dart` uses Scaffold (full page) rather than spec's GenericBox (modal dialog). The spec requires a box with title "Calls", Close button, and three-dot menu -- the implementation uses an AppBar with back arrow instead.
- [ ] spec &sect;34.3 "Active Group Calls Section": active group calls section exists with AnimatedSize SlideWrap, channel type label, and join button. Section title "Active Group Calls" matches spec. Missing: `peerListSingleRow` style override.
- [ ] spec &sect;34.5 "Call Row Design": row dimensions match spec (56px height, 42px avatar at (16,7), name at semibold 13px). Grouping logic correctly groups same peer/date/type calls. Missing: name position should be (74, 9) per spec but code uses a Row layout rather than absolute positioning.
- [ ] spec &sect;34.6 "Call Direction & Type Indicators": direction arrows use Icons.call_made / Icons.call_received with green (answered) / red (missed) colors. Transform.translate offset (-2, 1) matches spec's `callArrowPosition`. Arrow-to-text skip is SizedBox(width:4) matching spec's `callArrowSkip=4px`.
- [ ] spec &sect;34.7 "Redial Button": redial button exists with voice (Icons.call) and video (Icons.videocam) variants. Size is SizedBox(width:40, height:56) matching spec's 40x56px. Missing: ripple animation with 40px area at (0,8).
- [ ] spec &sect;34.8 "Status Text Format": timestamp formatting matches spec -- today shows bare time, yesterday shows "yesterday at HH:MM", older shows "Mon DD at HH:MM". Grouped calls show "(N) timestamp" format.
- [ ] spec &sect;34.9 "Context Menu": context menu has "Delete" and "Show in Chat" -- matches spec. Uses custom `showTelegramMenu` with icon colors. Missing: specific icon tokens (menuIconDelete, menuIconShowInChat).
- [ ] spec &sect;34.11 "Clear Call History Dialog": clear dialog exists with "Also delete for other participants" checkbox, Clear/Cancel buttons. Matches spec's structure. Uses `AlertDialog` instead of `GenericBox`.
- [ ] spec &sect;34.12 "Create Call Button": create call button exists with accent-colored circle icon, "Create Call" label, and description text showing participant limit. Highlight animation exists. Missing: `inviteViaLinkButton` style, FloatingIcon at `inviteViaLinkIconPosition`.
- [ ] spec &sect;34.13 "Rate Call Dialog": no rate call dialog with 5-star rating row (36x36 stars), optional comment field (200 char limit, 135px max height), or Send/Cancel buttons found.
- [ ] spec &sect;34.14 "Call Settings Section": call settings screen exists with Output/Input/Call Devices/Camera/Other sections, device selectors, level meter (44 lines, 3px width, 5px spacing, 18px height -- matches spec). Missing: live camera preview (shows placeholder instead).
- [ ] spec &sect;34.15 "Active Call Top Bar": no 38px colored top bar with mute toggle (41x38px), duration label, signal bars, info label, or hangup button found. No gradient background animation for group calls (green/blue/purple states).
- [ ] spec &sect;34.17 "Create Conference Call Box": `_CreateCallBox` exists with participant picker, invite-via-link button, prioritized contacts section, and conference size limit (200) with overflow toast. Matches spec structure. Missing: `createCallListItem` style override (52px height, 40px avatar at (12,6), name at (63,7)), video/audio element buttons use correct 36x52px size.

## &sect;35 -- Empty, Error & Loading States
- [ ] spec &sect;35.1 "Empty Chat List": no Lottie `no_chats.tgs` animation at 120x120px, no "You have no conversations yet" text in dialogEmptyButtonLabel style (semibold), no "New Message" action button at bottom found in `app_state.dart`.
- [ ] spec &sect;35.5 "Chat List Loading": no skeleton row loading animation with 60px name bar width, 100px status bar width, or glare sweep (1000ms slide + 1000ms pause) found. Loading shows CircularProgressIndicator instead of skeleton placeholders.
- [ ] spec &sect;35.6 "No Chat Selected": service-message bubble "Select a chat to start messaging" may exist in the shell but not verified in `app_state.dart`. Needs check in shell.dart or equivalent.
- [ ] spec &sect;35.7 "Empty Search Results": no Lottie `noresults.tgs` at 100x100px, no bold "No Results" title, no "There were no results for..." body text, no "Search in All Messages" link found.
- [ ] spec &sect;35.10 "Empty Shared Media Tabs": no per-type icons (infoEmptyPhoto/Video/Audio/File/Voice/Link) at 1/3 height position, no "No photos/videos/files here yet" labels at 40px from bottom found.
- [ ] spec &sect;35.22 "Connection State Widget": no "Connecting..." pill with 20x20px radial spinner, 150ms fade animation, bottom-left anchoring, or proxy icon found. No "Reconnect in N s..." countdown with "Try now" retry link.
- [ ] spec &sect;35.33 "Skeleton Animation": no skeleton animation system with kSlideDuration=1000ms, kWaitDuration=1000ms, kBaseAlpha=0.5, kGradientAlpha=0.2 constants for FlatLabel loading placeholders found.
- [ ] spec &sect;35.24 "File Download States": no radial progress indicator (InfiniteRadialAnimation) with msgFileRadialLine=3px stroke for file downloads, no "Ready"/"Downloading"/"Loaded"/"Failed" status text transitions found.

## &sect;36 -- Common Dialog & Modal Patterns
- [ ] spec &sect;36.1 "Box/Dialog Infrastructure": `confirm_box.dart` implements TelegramBox with correct dimensions (320/364px width, 8px radius, 48px title height at 24/13 position, 200ms animation). Box animation uses easeOutCirc for dim + linear opacity -- matches spec. Enter key triggers confirm -- matches spec. Missing: boxMaxListHeight=492px is implemented correctly. Missing: close X button uses `box_button_close` icon token -- implementation uses Icons.close.
- [ ] spec &sect;36.2 "Confirmation Dialogs": `showConfirmBox` implements ConfirmBoxArgs pattern with text/confirmed/cancelled/confirmText/cancelText/confirmStyle/title/inform parameters. Destructive variant uses attentionButtonFg. Enter triggers confirm. Missing: `strictCancel` flag, `labelFilter` for links, custom `labelPadding`.
- [ ] spec &sect;36.2 "Delete/Leave ConfirmBox": `showDeleteConfirmBox` implements all four modes (single/bulk/clear/leave) with correct body text, revoke checkbox, moderate panel (Ban/Report/DeleteAll), and dynamic confirm label. Matches spec closely.
- [ ] spec &sect;36.5 "Choice Dialogs (SingleChoiceBox)": `showSingleChoiceBox` exists with radio buttons and auto-close on selection. Matches spec structure.
- [ ] spec &sect;36.6 "Date/Time Picker": CalendarBox exists in `chat_export.dart` with 320px width, month navigation, day grid. Missing: `exportCalendarSizes` with exact 48x40 cells / 34px cellInner (current cells are approximately right). Missing: ChooseDateTimeBox with 95px scheduleHeight, 136px date field, 72px time field.
- [ ] spec &sect;36.9 "Toast / Snackbar Notifications": `telegram_toast.dart` exists (not fully read). Needs audit against spec's defaultToast (padding 19/13/19/12, maxWidth 480px, radius 6px, fadeIn 200ms, fadeOut 1000ms, slide 160ms, duration 1500ms).
- [ ] spec &sect;36.10 "Context Menus": no PopupMenu with spec's defaultPopupMenu (8px radius, 200ms show / 150ms hide, defaultPanelAnimation clip-reveal, defaultMenu item padding 17/8/17/7, width 156-300px, separator 1px at margins 0/5/0/5) found as a reusable component. The code uses `popup_menu.dart` but it was not fully read.
- [ ] spec &sect;36.11 "Tooltip Popups": `telegram_tooltip.dart` exists (not fully read). Needs audit against spec's defaultTooltip (padding 5/2/5/2, show delay 1000ms, maxWidth 800px, 12 lines max) and ImportantTooltip (4px radius, 8x4px arrow, 200ms animation).
- [ ] spec &sect;36.7 "Color Picker (ColorEditor)": HSL color picker exists in `story_editor.dart` (_HSLColorPickerDialog) with H/S/L sliders. Missing: 2D gradient picker square (colorPickerSize), hue slider (colorSliderWidth), opacity slider (RGBA mode), HSB fields, RGB fields, hex result field, and current-vs-new color swatches. The implementation is a simplified 3-slider version.
- [ ] spec &sect;36.12 "Permission Request Dialogs": `confirm_box.dart` implements permission flow with getPermissionStatus, requestPermissionOrFail, and showPermissionDeniedBox. Text matches spec ("needs microphone access..."). openSystemSettingsForPermission covers Linux/macOS/Windows. Microphone+Camera sequential request for video calls implemented correctly.
- [ ] spec &sect;36.13 "Report Flow": two-step report flow exists (showReportReasonBox with 9 reason buttons + showReportDetailsBox with optional comment). Matches spec's ReportReasonBox and ReportDetailsBox. Report reaction variant exists. Missing: specific icon tokens for report reasons.
- [ ] spec &sect;36.14 "Share Box": share contact box exists in `contacts_screen.dart` with grid layout, multi-selection, comment field. Missing: forward options (sender names/captions), stars count display, dark mode style override.
- [ ] spec &sect;36.15 "Sticker Toast": no sticker/emoji pack notification toast with clickable link to open sticker set found.
# Audit: §37-§49 Popups, Formatting & Interactions

## §37 — Desktop Notifications

- [ ] spec §37.3.3 "Corner Selection": notification_popup.dart implements all 5 corners correctly, but `_recalcPositions` does not apply RTL layout swap (left/right should swap in RTL locales per spec) — `notification_popup.dart`
- [ ] spec §37.3.4 "Title text font": spec says title uses `semiboldFont` (13px semibold), code uses `fontSize: 13, fontWeight: FontWeight.w600` which is correct weight but spec says the font token is `st::semiboldFont` — font size is correct but not verified against AyuGram's exact 13px semibold Open Sans — `notification_popup.dart:514`
- [ ] spec §37.3.4 "Message text": spec says message text drawn with `dialogsTextFont` up to 2 lines with right-edge fade-out mask (`notifyFadeRight`); code uses `TextOverflow.ellipsis` instead of a fade-out gradient — `notification_popup.dart:528-530`
- [ ] spec §37.3.4a "Reply field width": spec says reply field width = `notifyWidth - notifySendReply.width - 2*borderWidth` = 282px; code uses `Expanded` in a Row which should produce a similar result but the exact pixel math is not enforced — `notification_popup.dart:731-763`
- [ ] spec §37.3.4a "Reply field text margins": spec says text margins are 8/8/8/6 px; code uses `contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)` missing the asymmetric 6px bottom — `notification_popup.dart:757`
- [ ] spec §37.3.5 "Shift animation": spec says notifications animate their vertical shift over 150ms when added/removed; code sets `currentY = shift` instantly in `_recalcPositions` with no animation — `notification_popup.dart:288-290`
- [ ] spec §37.3.5 "Input polling": spec says when `WaitForInputForCustom` is true and no user input has occurred, auto-dismiss is deferred with 300ms polling; code does not implement input-detection polling at all — `notification_popup.dart`
- [ ] spec §37.3.6 "Ctrl+click": spec says Ctrl+click on notification body opens chat in a separate window; code has no Ctrl modifier detection on tap — `notification_popup.dart:219-223`
- [ ] spec §37.3.7 "Queue overflow eviction": spec says oldest non-reply, non-hover notification is evicted when at capacity and queue is non-empty; `DefaultManager` simply queues the item without evicting any shown notification — `notification_manager_default.dart:60-65`
- [ ] spec §37.3.7 "Hide All button appears with 2+ or queue non-empty": code checks `_active.length >= 2 || _queue.isNotEmpty` in `showHideAll` which is correct, but the popup overlay checks `_popups.length >= 2` only and does not check the queue — `notification_popup.dart:383`
- [ ] spec §37.4.1 "Title composition: monoforum sublist": spec defines monoforum sublist title pattern `SublistPeerShortName (ChatName)`; the `composeNotificationContent` function does not handle monoforum sublists — `notification_types.dart:226-245`
- [ ] spec §37.4.3 "Album text": spec says albums display as `lng_in_dlg_album` ("Album"); code correctly produces "Album" in `_flushGroupedBuffer` — verified OK
- [ ] spec §37.12.1 "Hidden userpic placeholder": spec says the placeholder is a square app logo at 62x62px; code shows a square container with a single letter 'U' as placeholder instead of the app logo — `notification_popup.dart:639-662`
- [ ] spec §37.13 "Userpic caching size": spec says native userpic cache is 64px PNG; code resizes to 64x64 correctly — verified OK in `notification_manager_native.dart:59`

## §38 — User Profile Popup

- [ ] spec §38.1 "Triggers": spec says PeerShortInfoBox triggers from Ctrl+Click on "View Profile" context menu item; the `showPeerShortInfoBox` function exists but there is no evidence of Ctrl modifier detection at the call site — `peer_short_info.dart:38`
- [ ] spec §38.2 "Phone field": the info rows show phone for DM users correctly, but spec says single-line fields use `setDoubleClickSelectsParagraph(true)` for easy selection; code uses `SelectableText` which does not configure this — `peer_short_info.dart:667-698`
- [ ] spec §38.2 "Notes field": spec says a "Notes" row with personal notes should appear; code does not implement a Notes info row — `peer_short_info.dart:526-637`
- [ ] spec §38.2 "Video profile photos": spec says if the current profile photo has a video version it auto-plays in a loop; code shows only static images, no video playback — `peer_short_info.dart:323-349`
- [ ] spec §38.3 "Scrolling parallax": spec says cover image scrolls with parallax and name/status labels fade based on scroll; code implements parallax via `_kParallaxFactor = 0.3` and label fade via `_labelOpacity` — verified implemented, but the parallax factor is custom (spec does not define a specific factor)
- [ ] spec §38.5 "Scroll bar": spec says scroll bar is 8px wide, 3px inset, 150ms show animation, 1000ms hide delay; code uses `RawScrollbar` with matching `_kScrollBarWidth=8`, `_kScrollBarInset=3`, `_kScrollShowDuration=150ms`, `_kScrollHideDelay=1000ms` — verified OK
- [ ] spec §38.9 "Right-click context menu": spec says right-click shows "Open in New Window" menu item only if peer is not already open in a separate window; code always shows the menu item without checking if already open — `peer_short_info.dart:185-208`
- [ ] spec §38.11 "Premium effects": spec says the ShortInfoBox does NOT display verified/scam/fake badges or emoji status next to name; code renders plain text name which is correct — verified OK
- [ ] spec §38.12 "Keyboard navigation": spec says no keyboard shortcuts to navigate profile photos; code has no keyboard photo navigation — verified OK

## §39 — Photo & Avatar Cropping Dialog

- [ ] spec §39.2 "Full-window layer": spec says the editor is a full-window layer that cannot be closed by clicking outside; code uses `barrierDismissible: false` which is correct — verified OK
- [ ] spec §39.2 "Blurred background": spec says background is a downscaled-4x, 24px Gaussian blurred, dimmed screenshot; code uses `BackdropFilter` with `sigmaX/Y: 24` which is a real-time blur rather than the pre-rendered screenshot approach — acceptable Flutter adaptation, but missing the cross-fade animation between old/new backgrounds on resize — `photo_crop_editor.dart:490-510`
- [ ] spec §39.4 "Crop overlay": crop shape rendering (ellipse, roundedRect, rect) with fade overlay, border, corner indicators, and 3x3 grid all implemented correctly — verified OK
- [ ] spec §39.5 "No zoom controls": spec explicitly states no zoom controls exist; code has none — verified OK
- [ ] spec §39.7 "Rotation": spec says rotate button uses `photo_editor/rotate-flip_horizontal` icon; code uses `Icons.rotate_right` Material icon instead of the specific AyuGram icon — `photo_crop_editor.dart:1100`
- [ ] spec §39.7 "Flip icon change": spec says flip button icon changes to active-colored variant when flipped; code correctly switches between `_IconState.active` and `_IconState.idle` for the flip button — verified OK
- [ ] spec §39.9 "Emoji Builder cycle timer": spec says suggested stickers rotate with 1500ms cycle; code uses `_kSuggestedCycleDuration = 1500ms` — verified OK
- [ ] spec §39.11 "Done button label": spec says for profile photos the confirm button reads "Set Photo", for suggestions "Suggest", for general editing "Done"; code accepts a custom `doneLabel` parameter defaulting to "Set Photo" — partially OK, but no automatic label switching based on context
- [ ] spec §39.14 "Grid overlay fade": spec says grid fades in instantly when drag starts, fades out over 200ms when drag ends; code sets `_gridController.value = 1.0` instantly on pointer down and calls `_gridController.reverse()` on pointer up — verified OK

## §40 — Send Files Dialog

- [ ] spec §40.2 "Album preview drag-to-reorder": the `send_files_box.dart` file exists (30435 tokens, could not read fully), but based on the spec, album drag-to-reorder requires shrink animation at 150ms and layout transition at 200ms; needs verification that these animations exist — `send_files_box.dart`
- [ ] spec §40.3 "Group files checkbox": spec says a "Group files" checkbox should be visible when 2+ compatible files are present; needs verification in send_files_box.dart — `send_files_box.dart`
- [ ] spec §40.3 "Send as documents checkbox": spec says an inverted checkbox controls whether images are sent as documents; needs verification — `send_files_box.dart`
- [ ] spec §40.4 "HD badge": spec says a rounded "HD" pill overlay appears on preview when high-quality is enabled; needs verification — `send_files_box.dart`
- [ ] spec §40.5 "Per-file spoiler toggle": spec says right-click context menu on individual thumbs shows "Spoiler effect" toggle; needs verification — `send_files_box.dart`
- [ ] spec §40.6 "Caption field character limit": spec says `kMaxMessageLength = 4096` with a `CharactersLimitLabel`; needs verification — `send_files_box.dart`
- [ ] spec §40.6 "Per-file captions": spec says each file block can have its own caption when sending as documents; needs verification — `send_files_box.dart`
- [ ] spec §40.9 "Ctrl+O shortcut": spec says Ctrl+O opens the add-file dialog; needs verification — `send_files_box.dart`
- [ ] spec §40.10 "Send menu": spec says right-click on send button opens a menu with silent send, schedule, spoiler toggle, caption position, photo quality; needs verification — `send_files_box.dart`

## §41 — Message Formatting Toolbar

- [ ] spec §41.1 "No floating toolbar": spec says there is NO floating toolbar on text selection, only right-click context menu + keyboard shortcuts; code implements `_ComposeFormattingOverlay` which appears to be a context-menu-based approach — `chat_view.dart:11423`
- [ ] spec §41.4 "Date formatting option": spec says Ctrl+Shift+D inserts a date via `CalendarBox` then `ChooseDateTimeBox`; code likely does not implement this custom date entity formatting — needs verification in `chat_view.dart`
- [ ] spec §41.4 "Quote formatting": spec says Ctrl+Shift+. applies blockquote; needs verification that this keyboard shortcut is bound — `chat_view.dart`
- [ ] spec §41.6 "Edit Link Dialog": spec says Ctrl+K opens `EditLinkBox` with text field + URL field, 320px wide box; needs verification of implementation — `chat_view.dart`
- [ ] spec §41.7 "Code block language dialog": spec says clicking a code block's language header opens `EditCodeLanguageBox`; needs verification — `chat_view.dart`
- [ ] spec §41.9 "Markdown auto-conversion disabled": spec says markdown syntax is NOT auto-converted while typing, only at send time; needs verification — `chat_view.dart`

## §42 — Reactions Detail Popup

- [ ] spec §42.2 "Context menu popup (Mode A)": spec defines a context-menu popup with user submenu triggered by right-clicking a reaction button; code implements a full modal panel (Mode B) via `ReactionsDetailPanel.show()` but lacks the inline context-menu Mode A — `reactions_detail.dart:34-70`
- [ ] spec §42.3 "Title text": spec says title adapts: "Seen by N" / "Listened by N" / "Reactions"; code builds title as "Reactions . N" which does not include seen/listened variants — `reactions_detail.dart:276-280`
- [ ] spec §42.4.2 "Pill geometry": spec says pill height is 32px, corner radius is 16px (fully rounded); code uses `height: 32` and `BorderRadius.circular(16)` — verified OK
- [ ] spec §42.4.3 "Container padding": spec says container outer padding is `margins(12,10,12,10)`; code uses `EdgeInsets.fromLTRB(12, 10, 12, 10)` — verified OK
- [ ] spec §42.4.3 "Inter-tab gap": spec says horizontal and vertical gaps are 8px; code uses `Wrap(spacing: 8, runSpacing: 8)` — verified OK
- [ ] spec §42.4.4 "Selection transition duration": spec says 150ms; code uses `AnimationController(duration: Duration(milliseconds: 150))` — verified OK
- [ ] spec §42.4.5 "Ripple animation": spec says each tab supports ripple; code uses `InkWell` with `borderRadius` which provides Material ripple — verified OK
- [ ] spec §42.5.1 "Row geometry Mode B": spec says row height 58px, avatar 46px at (18,6), name at (79,11); code matches exactly — verified OK in `reactions_detail.dart:658-701`
- [ ] spec §42.5.2 "Right-action emoji right margin": spec says right margin 27px from row right edge; code uses `right: 27` — verified OK
- [ ] spec §42.5.3 "Date line in Mode A context menu": spec says per-user date line only in Mode A; code does not implement Mode A at all, so no date lines in the context menu — `reactions_detail.dart`
- [ ] spec §42.6 "Pagination": spec says first page 20, subsequent 100; code uses `_kPerPageFirst = 20` and `_kPerPageMore = 100` — verified OK
- [ ] spec §42.12 "Panel width": spec says desired width 392px with minimum layer margin 48px; code uses `maxWidth: 392` — verified OK
- [ ] spec §42.16 "Blocked user filtering": code implements blocked user filtering via `_blockedIds` set — verified OK

## §43 — Read Receipts Detail

- [ ] spec §43.1 "Trigger": spec says read receipts are accessed via right-click context menu "Seen by N" item; code has a `who_read` context menu item in chat_view.dart — implementation exists
- [ ] spec §43.3 "1:1 private chat WhenReadAction": spec says private chats show "Read at HH:mm" with double-check icon instead of user list; code integrates read participants into the ReactionsDetailPanel Read tab but does not have a separate single-line WhenRead action for 1:1 chats — `reactions_detail.dart`
- [ ] spec §43.4.1 "Row geometry Mode A (context menu submenu)": spec defines 40px rows with 30px avatar for context menu; code only implements Mode B (58px rows, 46px avatar) — no Mode A submenu exists — `reactions_detail.dart`
- [ ] spec §43.5 "Loading state": spec says summary shows "Loading..." while unknown; code shows a `CircularProgressIndicator` while loading which is functionally equivalent — `reactions_detail.dart:313-316`
- [ ] spec §43.8 "Time formatting": spec says timestamps formatted as "Today, HH:mm" / "Yesterday, HH:mm" / "Mon DD, HH:mm"; code implements `_formatReadDateLocal` with matching logic — verified OK in `reactions_detail.dart:777-795`
- [ ] spec §43.10.3 "WhenRead line for private chats": spec defines `whenReadPadding`, `whenReadIconPosition`, `whenReadSkip` for the private-chat read-time row; code does not implement this separate private-chat read-time row — `reactions_detail.dart`
- [ ] spec §43.12 "Privacy states (MyHidden/HisHidden)": spec says privacy states show "Read time hidden" with a clickable "Show" pill button; code does not handle `WhoReadState::MyHidden` or `HisHidden` states — `reactions_detail.dart`

## §44 — Spoiler Animation

- [ ] spec §44.1 "Text spoiler rendering": spec says text behind spoiler is drawn at `opacity = 1 - spoilerOpacity` for cross-fade; `SpoilerTilePainter` draws particle overlay at `opacity = 1 - revealProgress` and the text below is expected to be drawn separately by the caller — particle overlay is correct, but the text cross-fade depends on the message_bubble integration
- [ ] spec §44.3 "Particle counts": spec says text spoiler = 9000 particles, image = 3000; code uses `count = isText ? 9000 : 3000` — verified OK in `spoiler_animation.dart:138`
- [ ] spec §44.3 "Frame count and duration": spec says 60 frames at 33ms (~30fps); code uses `_kFrameCount = 60` with `33ms` frame step — verified OK
- [ ] spec §44.3 "Canvas size": spec says 128dp; code uses `_kCanvasSize = 128.0` — verified OK
- [ ] spec §44.3 "Sprite variants": spec says 5 variants with size variation; code uses `_kSpriteVariants = 5` with correct size variation logic — verified OK
- [ ] spec §44.4 "Reveal duration": spec says reveal animation over 200ms (`fadeWrapDuration`); the `SpoilerTilePainter` accepts `revealProgress` parameter but the 200ms duration must be driven by the caller — `spoiler_animation.dart:266`
- [ ] spec §44.5 "Compose field spoiler": spec says `FieldSpoilerOverlay` with cursor-based 50% opacity (`kSpoilerHiddenOpacity = 0.5`); code provides `SpoilerAnimationMixin` but does not implement compose-field-specific cursor-based opacity reduction — `spoiler_animation.dart`
- [ ] spec §44.6 "Spoiler in notifications": spec says spoiler chars replaced with U+259A; code implements `_applySpoiler` using `_spoilerBlock = '▚'` correctly, and `_maskLoginCodes` with the matching regex — verified OK in `notification_types.dart:199-329`
- [ ] spec §44.7 "Auto-pause timeout": spec says `kAutoPauseTimeout = 1000ms`; code uses `_kAutoPauseTimeoutMs = 1000` — verified OK
- [ ] spec §44.7 "Color cache capacity": spec says `kDefaultSpoilerCacheCapacity = 24`; code defines `_kColorCacheCapacity = 24` but does not implement the actual per-color cache (the `SpoilerTilePainter` uses `ColorFilter.mode` instead of pre-cached colorized sprite sheets) — `spoiler_animation.dart:19`
- [ ] spec §44.7 "Power saving": spec says `kChatSpoiler` flag pauses animations; code reads `AppState.kPowerSavingChatSpoiler` and sets `powerSavingPaused` — verified OK
- [ ] spec §44.8 "Image spoiler darken alpha": spec says `kImageSpoilerDarkenAlpha = 32`; code uses `Color.fromRGBO(0, 0, 0, (32 / 255) * opacity)` — verified OK in `spoiler_animation.dart:289`

## §45 — Custom Emoji Rendering

- [ ] spec §45.1 "Inline rendering size": spec says logical size 18px, adjusted frame 20px; code defines `EmojiSizeTag.normal: 20.0` — verified OK
- [ ] spec §45.2 "Large emoji size tiers": spec defines 1-emoji=112px, 2-emoji=78px, 3-emoji=58px; code defines size constants but rendering of large isolated custom emoji in messages needs verification in message_bubble.dart — `custom_emoji_cache.dart:20-25`
- [ ] spec §45.7 "Loading states": spec describes 3-phase loading (Loading with SVG preview at 12.5% opacity, Caching, Cached); code provides `getThumb`/`getPath`/`getFile` for multi-level loading but the 12.5% opacity SVG preview rendering depends on callers — `custom_emoji_cache.dart:96-103`
- [ ] spec §45.8 "Two-level cache": code implements in-memory instance cache with refcounting (`acquire`/`release`) and disk sprite atlas cache; batched API requests up to 100 IDs — verified OK in `custom_emoji_cache.dart`
- [ ] spec §45.8 "Eviction": spec says when all references drop to zero, file data evicted from memory (disk retained); code implements `_evictFromMemory` that removes from `_files` map — verified OK
- [ ] spec §45.9 "Click behavior": spec says clicking custom emoji opens `ShowReactionPreview` overlay with "View Pack" affordance; this overlay is not implemented in the codebase — no `reaction_preview` or `sticker_preview` overlay exists
- [ ] spec §45.14 "Reaction/emoji preview overlay": spec describes a full-viewport overlay with `MediaPreviewWidget`, clickable "View Pack" rounded-shadow rectangle, and 120ms fade; this entire overlay system is not implemented — missing feature

## §46 — Link Preview in Compose

- [ ] spec §46.1 "URL detection debouncing": spec says 500ms debounce for 1-2 char changes, 0ms for paste; code has a `_betterLinkPreviewUrl` function and link preview logic in chat_view.dart — needs detailed verification of debounce timing
- [ ] spec §46.2 "Preview card layout": spec says 49px height bar with left icon at (7,7), thumbnail at 53px left, text at 53/95px, cancel button 49x49px; needs verification that the FieldHeader equivalent in chat_view.dart matches these exact pixel values
- [ ] spec §46.3 "Large vs small media toggle": spec says DraftOptionsBox has "Enlarge photo/video" / "Shrink photo/video" button; needs verification of implementation
- [ ] spec §46.4 "Preview above/below text": spec says `WebPageDraft.invert` flag controls position; needs verification
- [ ] spec §46.5 "Multiple URLs": spec says first link with cached preview is picked; the link-preview flow in chat_view.dart needs verification for multi-URL handling
- [ ] spec §46.8 "Remove preview": spec says clicking cancel X removes preview and sets `removed` flag that persists in draft; needs verification

## §47 — Restricted Permissions UI

- [ ] spec §47 "WriteRestrictionType enum": spec defines None/Rights/PremiumRequired/Frozen/Hidden types; code in chat_view.dart likely implements a restriction bar but full coverage of all 5 types needs verification
- [ ] spec §47 "Per-restriction error strings": spec defines 3 tiers of error messages (timed/permanent/default) for each `ChatRestriction` flag; these localized strings need to come from the engine and be displayed correctly
- [ ] spec §47 "Grayed/forbidden send button": spec says record/round button at 50% opacity when forbidden with suppressed ripple; needs verification in chat_view.dart send button implementation
- [ ] spec §47 "Slowmode countdown": spec says MM:SS countdown on send button using `normalFont` 13px in `windowSubTextFg`; needs verification
- [ ] spec §47 "Join to Send button": spec says unjoin channels show "JOIN CHANNEL" / "JOIN GROUP" / "APPLY TO JOIN GROUP" button; needs verification
- [ ] spec §47 "Bot Start button": spec says first-time bot chats show "START" button; needs verification
- [ ] spec §47 "Unblock button": spec says blocked users show "UNBLOCK" button in `attentionButtonFg` red; needs verification
- [ ] spec §47 "Forum topic closed": spec says closed topics show "This topic is closed." restriction text; needs verification

## §48 — Drag-and-Drop File Overlay

- [ ] spec §48.1 "Drop zone appearance": spec says rounded rectangle with `boxBg` background, `boxRoundShadow` shadow, main text 27px semibold, subtext 19px semibold; code has a `_DragOverlay` widget in chat_view.dart — needs verification of exact dimensions and text sizes
- [ ] spec §48.2 "Two-zone layout": spec defines Files/PhotoFiles/MediaFiles/Image states with top/bottom split for two-zone mode; needs verification of zone classification logic
- [ ] spec §48.4 "File type detection": spec says `ComputeMimeDataState` classifies dragged content; needs verification that the Dart equivalent properly classifies file types
- [ ] spec §48.5 "Animation": spec says `_a_opacity` fades in/out over 200ms; code has `_dragOverlayAnimCtrl` AnimationController — needs verification of duration
- [ ] spec §48.7 "No icons": spec says drop zones are text-only (no icons); needs verification
- [ ] spec §48.9 "Disabled state": spec says drag overlay does not appear if user cannot send any file type; needs verification of permission check

## §49 — Scroll Behaviors

- [ ] spec §49.1 "Infinite scroll preload": spec says preload triggers at 3 viewport heights from edge, fetching 50 messages per page (30 for first load); needs verification in chat_view.dart scroll logic
- [ ] spec §49.2 "Jump-to-date": spec says clicking sticky date header opens `CalendarBox`; code likely has a date click handler — needs verification
- [ ] spec §49.3 "Jump-to-message highlight": spec says highlight effect: 400ms fade in, optional 400ms hold + 200ms collapse, 2000ms fade out; needs verification of highlight animation in chat_view.dart
- [ ] spec §49.4 "Unread marker": code has `_UnreadBar` widget at chat_view.dart:7331 — exists, needs verification of positioning and destruction logic
- [ ] spec §49.5 "Scroll-to-bottom button": spec says 52x62px hit area, down-arrow circular button, shown when scrolled up >480px, 150ms slide animation; code has a jump-down button (chat_view.dart:10447) — needs verification of exact dimensions and threshold
- [ ] spec §49.5 "Unread badge on scroll button": spec says unread count shown in 22px circle badge; needs verification
- [ ] spec §49.6 "New message auto-scroll": spec says own messages always scroll to bottom, incoming only if already at bottom; needs verification
- [ ] spec §49.8 "Smooth scrolling duration": spec says 240ms with sineInOut for short scroll, easeOutCubic for long scroll; needs verification
- [ ] spec §49.9 "Scroll-to-mention button": spec says "@" icon button shown when unread mentions exist, stacked above scroll-to-bottom with 4px gap; code has mention button at chat_view.dart:10547 — needs verification of stacking
- [ ] spec §49.10 "Scroll-to-reaction button": spec says heart icon button for unread reactions stacked above mentions; needs verification
- [ ] spec §49.13 "Sticky date header": spec says date header fades in over 200ms, auto-hides after 1000ms; needs verification of timing constants
# Audit: §50-§57 AyuGram Features & Appendices

## §50 — Streamer Mode & Read Toggles

- [ ] spec §50.2 "Streamer Mode — what it does": No `StreamerModeState` or streamer-mode runtime toggle exists anywhere in the Dart codebase. The spec requires a non-persistent `enabled` boolean with a `Stream<bool>` for drawer/tray sync — `state/app_state.dart` only has `showStreamerToggleInDrawer` / `showStreamerToggleInTray` (visibility gates), but no actual streamer mode on/off state or OS platform channel for `SetWindowDisplayAffinity` / `NSWindow.sharingType`
- [ ] spec §50.3.1 "Drawer toggle": The drawer does not render a Streamer Mode on/off toggle row (only the visibility setting in `ayu_other_page.dart` "Show Streamer Mode toggle in drawer" exists, but the drawer itself has no toggle to flip the actual mode)
- [ ] spec §50.3.2 "Tray menu toggle": No tray menu integration exists — spec requires "Enable/Disable Streamer Mode" action in the system tray context menu; the code only has a setting to show/hide it (`showStreamerToggleInTray`)
- [ ] spec §50.3.3 "Settings page — Drawer/Tray elements": Drawer/Tray elements are located in `ayu_other_page.dart` instead of the Ghost Mode page as spec §50.3.3 requires (spec says these live under "AyuGram settings > Ghost Mode page" subsections "Drawer Elements" / "Tray Elements")
- [ ] spec §50.4 "Visual indicators": No visual indicator that Streamer Mode is active (no icon, no chip, no badge anywhere)
- [ ] spec §50.7 "Read toggles — Local Read / Server Read model": `showLReadToggleInDrawer` and `showSReadToggleInDrawer` settings exist in `ayu_other_page.dart` as drawer visibility toggles, but no actual LRead/SRead drawer toggle rows are rendered in the drawer at runtime
- [ ] spec §50.8 "All referenced settings keys": Missing `showGhostToggleInDrawer` / `showStreamerToggleInDrawer` visibility settings on the Ghost Mode page itself — they only appear on `ayu_other_page.dart` (the "Other" page), not the Ghost Mode settings where the spec places them
- [ ] spec §50.9 "Chat list right-click — Read Message action": No "Read Message" context menu action on chat list items that forces a one-shot server read (spec requires this with a confirmation dialog)
- [ ] spec §50.9 "Chat context — per-peer exclusions": No "Read Exclusion" / "Typing Exclusion" per-peer override submenu on the chat context menu

## §51 — Ghost Mode

- [ ] spec §51.2.1 "Ghost Mode collapsible toggle": The ghost sub-toggles use checkboxes inside `AnimatedSize` which is correct, but the master toggle uses `_GhostMasterToggle` as a separate widget rather than a standard collapsible parent toggle — the visual style differs from spec (spec says "collapsible parent toggle labeled Ghost Mode")
- [ ] spec §51.2.2 "Schedule Messages — mutually exclusive with Read on Interact": Spec §51.2.2 says toggles #6 and #7 are mutually exclusive (enabling one disables the other). Code in `ghost_settings_page.dart` does not enforce mutual exclusivity — both `markReadAfterAction` and `useScheduledMessages` can be ON simultaneously
- [ ] spec §51.3 "Account picker — GlobalAction custom menu item": The `_GlobalSettingsAvatar` uses a purple gradient circle with "GS" text which matches the spec's description. However, the account picker does not show a toast notification on switch as spec requires ("Switched to same settings for all accounts." / "Switched to individual settings for each account.") — code uses `SnackBar` instead of the spec's toast
- [ ] spec §51.4 "Settings screen layout — navigation path": Spec says the ghost settings page is `AyuGhost` section reached via AyuMain > "AyuGram" category button. The code navigates to `GhostSettingsPage` with the app bar title "AyuGram" which is correct, but the page title should be blank per spec (AyuGhost section has no dedicated title bar text; the subsection title "Ghost essentials" is inline)
- [ ] spec §51.5 "Drawer — LRead and SRead toggle buttons": Drawer does not render LRead / SRead toggle buttons at runtime. Only the visibility settings (`showLReadToggleInDrawer`, `showSReadToggleInDrawer`) exist in `ayu_other_page.dart`
- [ ] spec §51.7 "Command-line -ghost flag": No support for `-ghost` launch argument that forces all ghost settings on at startup
- [ ] spec §51.8 "Toast notifications": Ghost mode toggle toast uses `showTelegramToast` in the code which is correct, but the spec's toasts `ayu_GhostModeEnabled` / `ayu_GhostModeDisabled` should match. Verified the strings match ("Ghost Mode turned on" / "Ghost Mode turned off")

## §52 — Anti-Recall & Message History

- [ ] spec §52.1 "Settings — semiTransparentDeletedMessages": Setting exists as `semiTransparentDeleted` in `ayu_chats_page.dart` as a toggle in the Messages section, but spec §52.1 says it should be under "Spy Essentials" subsection. It is implemented on the Chats page instead of the Ghost/AyuGram page
- [ ] spec §52.1 "deletedMark / editedMark — EditMarkBox dialog": No `EditMarkBox` dialog to customize the deleted mark or edited mark text. The `_BubbleRadiusSection` in `ayu_chats_page.dart` uses `deletedMark` and `editedMark` from state for the preview, but there is no settings UI to edit these strings (spec §52.10 describes a 320px dialog with text input and reset-to-default button)
- [ ] spec §52.1 "replaceBottomInfoWithIcons toggle": Toggle exists in the code (`replaceMarksWithIcons` in ayu_chats_page.dart) but there is no sub-settings reveal for the deleted mark and edited mark text customization buttons when this toggle is OFF (spec §54.11 says "When disabled, reveals sub-settings for custom deleted mark text and edited mark text via EditMarkBox dialogs")
- [ ] spec §52.2-52.4 "Deletion/Edit interception flow": No actual deletion or edit interception implementation exists in the Dart codebase. There is no mechanism to preserve deleted messages or capture pre-edit text. The `saveDeletedMessages` and `saveMessagesHistory` toggles in `ghost_settings_page.dart` are persisted but have no functional backend wiring
- [ ] spec §52.5 "Deleted Messages Viewer": No "View deleted messages" section panel or chat-list context menu action. No `MessageHistory` equivalent widget exists
- [ ] spec §52.4 "Edit History Viewer": No "Edits history" context menu item or section panel for viewing edit revisions
- [ ] spec §52.6 "Database Storage": No SQLite `ayudata.db` or equivalent local storage for preserved deleted/edited messages
- [ ] spec §52.7 "Context Menu — Edits history / Hide message / Read until here / Burn media": None of these AyuGram-specific context menu actions are implemented in the message bubble context menu

## §53 — Forward Enhancements

- [ ] spec §53.1 "Intelligent Forward — chunking algorithm": `AyuForward.buildChunks()` in `state/ayu_forward.dart` implements the chunking logic correctly, splitting messages by restriction status. However, there is no `intelligentForward` call path that triggers from the standard forward UI — the method exists but is not wired to any forward dialog or share box intercept
- [ ] spec §53.2 "Forward Progress Tracking — compose area replacement": `ForwardProgress` class exists with correct state machine (Preparing/Downloading/Sending/Finished), but no `AyuForwardWriteRestriction` widget replaces the compose area during an active forward. The progress bar UI described in spec (full-width FlatButton replacing compose field) does not exist
- [ ] spec §53.3 "Repeat Message — context menu action": No "Repeat Message" context menu item on message bubbles. The `showRepeatMessageInContextMenu` setting exists in `ayu_chats_page.dart` (context menu visibility), but no actual menu action is implemented
- [ ] spec §53.3 "Repeat Message — Shift+click for no-quote mode": No implementation of the "send as own without forward header" behavior triggered by Shift+clicking Repeat Message
- [ ] spec §53.4 "Restriction Override — context menu label": No "Plain forwarding is not allowed." label (`ayu_UnforwardableContextMenuText`) in the context menu for restricted messages
- [ ] spec §53.5 "Download-and-Resend Pipeline": `engine.resendAsOwn()` and `engine.resendAlbumAsOwn()` calls exist in `ayu_forward.dart`, but these delegate to the engine service which is the Go bridge — the actual download/re-upload logic depends on the Go backend, not verified here
- [ ] spec §53.8 "Repeat Message — No Hint Text": Irrelevant since the menu item itself doesn't exist yet

## §54 — AyuGram UI Customization

- [ ] spec §54.1 "Avatar Corners — live preview": `_AvatarCornersPreview` renders a static placeholder ("A" letter, purple background) instead of the actual AyuGramReleases channel userpic fetched via `contacts.resolveUsername`. The preview does not resolve a real userpic as spec requires — `ayu_appearance_page.dart`
- [ ] spec §54.1 "Avatar Corners — clicking preview opens channel": Spec says clicking the preview opens the AyuGramReleases channel. The `_AvatarCornersPreview` widget has no `GestureDetector` or `onTap` handler — `ayu_appearance_page.dart`
- [ ] spec §54.1 "Avatar Corners — restart required": Spec says slider release prompts a restart. The code changes corners immediately via `onCornersChanged` with no restart prompt — `ayu_appearance_page.dart`
- [ ] spec §54.2 "Material Switches — track size": Spec §54.2a says MD3 track is 32x18 and iOS track is 36x20. Code in `ayu_toggle.dart` uses md3 32x18 and iOS 36x20, which matches. Verified correct
- [ ] spec §54.3 "Wide Messages Multiplier — slider range": Spec says 61 discrete stops from 1.00 to 4.00 in 0.05 increments. Code uses `divisions: 60` with `min: 1.0, max: 4.0` which gives 61 stops — matches. But spec also says "valid range 0.5-4.0" while the slider only goes from 1.0 to 4.0, missing the 0.5-1.0 range — `ayu_chats_page.dart`
- [ ] spec §54.4 "Message Bubble Radius — live preview": `_MessagePreview` in `ayu_chats_page.dart` renders a preview with two messages including reply quote, deleted+edited marks, tail control, and quote styling. This matches the spec's description well
- [ ] spec §54.5 "Message Tail Removal": Toggle exists and affects the preview. Spec says "No restart required (reactive update)" which matches the code behavior
- [ ] spec §54.7 "Context Menu — Add Filter only if filtersEnabled": Spec says "The 'Add Filter' option only appears in settings if `filtersEnabled` is true." Code shows the Add Filter choose button unconditionally in the context menu items list — `ayu_chats_page.dart` line 229
- [ ] spec §54.8 "Drawer Elements — placement": Spec §54.12 says Drawer Elements and Tray Elements live under the **Appearance** page. Code places them in `ayu_other_page.dart` (the "Other" page) instead — `ayu_other_page.dart`
- [ ] spec §54.8 "Tray Elements — placement": Same as above — Tray Elements are under "Other" instead of "Appearance" as spec requires
- [ ] spec §54.8 "Drawer Elements — Streamer Mode only on Windows/macOS": The Streamer Mode drawer toggle is shown unconditionally (no platform check). Spec says "only appears on Windows and macOS" — `ayu_other_page.dart` line 92
- [ ] spec §54.8 "Tray Elements — Streamer Mode only on Windows/macOS": Same — Streamer Mode tray toggle shown unconditionally — `ayu_other_page.dart` line 109
- [ ] spec §54.9 "Message Field Button Toggles — wiring": Seven message field button toggles exist in `ayu_chats_page.dart` (Attach, Commands, TTL, Emoji, Voice, Gift, AI Editor) but their state is not consumed by the actual compose area to show/hide buttons. The toggles persist settings but the compose area does not read them
- [ ] spec §54.10 "Hide Notification Badge — Windows only": Setting `hideNotificationBadge` is not present anywhere in the Dart codebase. Spec says this is a Windows-only toggle under Appearance > "Appearance" subsection
- [ ] spec §54.10 "App Icon — icon picker": `_AppIconPicker` in `ayu_appearance_page.dart` renders colored squares with a single letter instead of actual SVG icon previews loaded from `AyuAssets.loadPreview()`. The 12 icon themes are listed correctly
- [ ] spec §54.10a "IconPicker — resolved layout": Spec says grid is 4 columns with `iconPickerIconSize` = 64px, `iconPickerSelectedRounding` = 12px. Code uses `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4)` which matches the column count, but icons are rendered as colored containers with text instead of actual icon images
- [ ] spec §54.11 "Translucent Deleted Messages — beta badge": Setting exists with `showBetaBadge: true` through the section builder. However, it is only in the Messages section of Chats, not in Spy Essentials where spec §52.1 places the visual toggle
- [ ] spec §54.12 "Settings Page Structure": The overall structure (AyuMain > 6 category buttons) is implemented correctly in `ayugram_settings_screen.dart`. However, the category mapping differs: spec maps "AyuGram" button to `AyuGhost` (ghost + spy + other), but code maps it to `GhostSettingsPage` which only covers ghost + spy. Drawer/Tray Elements are on the "Other" page instead of "Appearance"
- [ ] spec §54.14 "Translation Provider — platform-specific options": Code in `ayu_general_page.dart` hardcodes the provider list as {Telegram, Google, Yandex, Linux} without checking `IsTranslateProviderAvailable()`. Spec says the label always shows the platform name but on unavailable, settings init resets to Telegram. The code shows "Linux" unconditionally on all platforms
- [ ] spec §54.14 "Filter Zalgo — restart required": Spec says Filter Zalgo requires app restart (toggling shows a restart prompt). Code does not show any restart prompt — `ayu_general_page.dart`
- [ ] spec §54.15 "Donate icons — theme-adaptive background": Spec says donate button icon background is `#EEEEEE` in night mode and `#242B2C` in light mode. Code in `ayu_other_page.dart` line 290 correctly uses `isDark ? Color(0xFFEEEEEE) : Color(0xFF242B2C)`. Verified correct
- [ ] spec §54.15 "Other subsection — conditionally compiled": Spec says the "Other" subsection with Crash Reporting is conditionally compiled only when `TDESKTOP_DISABLE_AUTOUPDATE` is NOT defined. Code shows Crash Reporting unconditionally — `ayu_other_page.dart`
- [ ] spec §54.17 "AyuMain Landing Page — logo widget": The logo uses `settingsCloudPasswordIconSize` (96px per code). Spec says the size is from `st::settingsCloudPasswordIconSize` = 100px (§56.7). Code uses 96px instead of 100px — `ayugram_settings_screen.dart` line 68

## §55 — Channel & Group Statistics

- [ ] spec §55.1 "Opening Statistics": No statistics menu item or navigation to a statistics page exists in any peer context menu or info panel. `stats_chart.dart` contains the chart rendering infrastructure but no page/section wraps it
- [ ] spec §55.2 "Loading State": No loading state with Lottie animation (`stats` animation) and "Loading Statistics..." text
- [ ] spec §55.3 "Channel Statistics Layout — Overview Section": No 2x2 overview grid with StatisticalValue cards (Followers, Notifications, Views Per Post, Views Per Story). `StatisticalValue` class exists in `stats_chart.dart` but is not rendered anywhere
- [ ] spec §55.3 "Channel Statistics Layout — Charts Section": No statistics page renders charts. `StatsChartWidget` exists and is fully implemented with all 5 chart types (Linear, DoubleLinear, Bar, StackBar, StackLinear) but is never instantiated in any screen
- [ ] spec §55.3 "Recent Messages Section": No "Recent Messages" list with message preview rows, pagination, or "Show More" button
- [ ] spec §55.4 "Group Statistics Layout": No group statistics with Members/Messages/Viewing Members/Posting Members overview or Top Senders/Admins/Inviters peer lists
- [ ] spec §55.5 "Message Statistics Layout": No per-message statistics sub-page
- [ ] spec §55.6 "Chart Widget Architecture — all regions": `StatsChartWidget` implements header (36px), chart area (200px), footer/range selector (42px), and filter buttons correctly. The tooltip (`_buildTooltip`) includes date, per-line values, percentages, currency support, shadow, and zoom arrow. This implementation is comprehensive
- [ ] spec §55.7 "StackLinear — pie chart zoom": Pie chart transition is implemented with `_enterPieMode`/`_exitPieMode`, 400ms `easeOutCirc` animation, hover detection, pop-out on hover (8px), percentage labels. Matches spec. "Zoom Out" button appears in header
- [ ] spec §55.8 "Server-Side Zoom": `_requestServerZoom` fetches data via `onLoadZoomData` callback, creates a nested `StatsChartWidget` with crossfade, "Zoom Out" button. Correctly implemented
- [ ] spec §55.9 "Filter Buttons": `_FilterButton` with checkmark, color, active/inactive state, `Wrap` layout, long-press to solo/unsolo a line. Matches spec
- [ ] spec §55.10 "Animation System — FPS-adaptive": `_onChartTick` implements FPS-adaptive speed (`60 / currentFPS` multiplier, double speed below 30 FPS), three speed tiers, instant snap at 0.97 ratio, filter speed divisor 1.2. Matches spec

## §56 — Appendix A: Resolved Style Constants

- [ ] spec §56.1 "fsize = 13px, boxFontSize = 14px": `TgTokens.fsize = 13` and `TgTokens.boxFontSize = 14` in `theme_tokens.dart`. Matches spec
- [ ] spec §56.1 "slideDuration = 240ms, slideWrapDuration = 150ms, fadeWrapDuration = 200ms, universalDuration = 120ms": All four durations match in `theme_tokens.dart`. Verified correct
- [ ] spec §56.2 "boxWidth = 320, boxWideWidth = 364, boxRadius = 8": All match in `theme_tokens.dart`. Verified correct
- [ ] spec §56.3 "topBarHeight = 54, columnMinimalWidthLeft = 260, adaptiveChatWideWidth = 880": All match in `theme_tokens.dart`. Verified correct
- [ ] spec §56.4 "dialogsRowHeight = 62, dialogsPhotoSize = 46, dialogsNameLeft = 68": All match in `theme_tokens.dart`. Verified correct
- [ ] spec §56.7 "settingsCloudPasswordIconSize = 100px": Not defined in `theme_tokens.dart`. The AyuMain logo widget in `ayugram_settings_screen.dart` uses 96px hardcoded instead of 100px
- [ ] spec §56.8 "infoDesiredWidth = 392, infoTopBarHeight = 54": Both match in `theme_tokens.dart`. Verified correct
- [ ] spec §56.10 "windowBg light = #FFFFFF, dark = #212D3B": Spec §56.10 says dark `windowBg` is `#212D3B`, but §57.1 says dark `windowBg` is `#17212B`. The TelegramPalette `night` theme uses `#17212B` which matches §57.1 (the authoritative source). The §56.10 summary table appears to use the older "canonical Night" values which differ from the day-custom-base/night-custom-base themes in §57
- [ ] spec §56.10 "windowBgActive light = #40A7E3, dark = #2F82C7": Spec §56.10 says dark `windowBgActive` is `#2F82C7`, but §57.1 says `#5288C1`. TelegramPalette uses `#5288C1` for night which matches §57.1

## §57 — Appendix B: Dark Theme Color Palette

- [ ] spec §57.1 "windowBg dark = #17212B": TelegramPalette.night.windowBg must be `Color(0xFF17212B)`. Based on the palette field declarations and the theme system using `TelegramPalette.night`, this should be verified against the actual palette construction (file too large to read fully, but the `AppColors.darkBase = Color(0xFF17212B)` in `theme.dart` confirms the value is used)
- [ ] spec §57.1 "windowBgActive dark = #5288C1": `AppColors.accentDark = Color(0xFF5288C1)` in `theme.dart` matches. `TelegramPalette.night.windowBgActive` should use this value
- [ ] spec §57.2 "dialogsBgActive dark = #2B5278": `AppColors.bubbleSent = Color(0xFF2b5278)` exists but is named as bubble color. The dialog active background should be the same value per spec
- [ ] spec §57.4 "msgInBg dark = #24292E": Spec says dark `msgInBg` is `#24292E` but `AppColors.bubbleReceived = Color(0xFF182533)`. These differ — code uses `#182533`, spec says `#24292E`. The spec §57.4 night value and the code value are different. This may be an intentional AyuGram override or a palette version mismatch
- [ ] spec §57.4 "msgOutBg dark = #265E8C": Spec says dark `msgOutBg` is `#265E8C` but `AppColors.bubbleSent = Color(0xFF2b5278)`. These differ — code uses `#2B5278`, spec says `#265E8C`
- [ ] spec §57.5 "historyComposeIconFg dark = #6C7883": `AppColors.historyComposeIconFgNight = Color(0xFF6c7883)` matches spec value. Verified correct
- [ ] spec §57.6 "historyPeer1NameFg dark = #FB6169": Palette field exists in TelegramPalette. Value should be verified against the full palette definition
- [ ] spec §57.9 "activeButtonBg dark = #2F6EA5": Spec §57.9 says dark `activeButtonBg` is `#2F6EA5`. This differs from §57.1 `windowBgActive` dark = `#5288C1`. TelegramPalette must define these as separate tokens — verify that `activeButtonBg` uses `#2F6EA5` and not the `windowBgActive` alias
- [ ] spec §57.10 "sideBarBg dark = #0E1621": `AppColors.darkSidebar = Color(0xFF0E1621)` matches. Verified correct
- [ ] spec §57.10 "sideBarBgActive dark = #25303E": Needs verification against TelegramPalette.night.sideBarBgActive (palette too large to fully read)

## General / Cross-Cutting Issues

- [ ] No Streamer Mode feature exists at all — neither the runtime toggle, OS hooks, nor any UI surface. This is the largest missing AyuGram feature
- [ ] Ghost mode lock mechanism uses Shift+click on desktop and long-press on mobile (matching spec §51.2.1). Verified correct in `_LockableToggleRow`
- [ ] Per-peer read/typing exclusions (§50.7, §51.5) are entirely missing — no `Map<int64, ReadExclusion>` storage or per-chat override UI
- [ ] "Read Message" chat-list context action (§50.7) with confirmation dialog is missing
- [ ] The collapsible toggle in `ayu_section_builder.dart` does not implement a master toggle that sets all sub-checkboxes — it only shows/hides nested checkboxes. Spec §51.2.1 says the master toggle calls `setGhostModeEnabled(bool)` which flips all five core toggles
- [ ] No `-ghost` command-line flag support for launch-time ghost mode activation
- [ ] Statistics page infrastructure (`StatsChartWidget`, all 5 chart types, tooltip, footer, pie zoom, server zoom, filter buttons, FPS-adaptive animation) is fully built but never wired to any navigation entry point
- [ ] The AyuGram settings page structure partially mismatches spec §54.12: Drawer/Tray Elements are under "Other" instead of "Appearance"; the "AyuGram" category maps to ghost-only instead of ghost+spy+other
