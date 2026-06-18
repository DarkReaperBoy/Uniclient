# AyuGram UI Port — Progress & Findings (Phase 1)

Faithful, component-by-component port of AyuGram Desktop's UI into the Flutter app,
done bit by bit. Each component is ported against the **local AyuGram C++ source**
(`/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/`) as ground truth — NOT
the lossy spec doc — then built + screenshot-verified against the running app.

## Status
| Component | Status | Notes |
|---|---|---|
| Chat list row | ✅ committed (`dac06254`) | 18 fidelity fixes; biggest = AyuGram 3-state color cascade (active→hover→normal, solid `dialogsBgOver` hover swap) that was faked with a translucent overlay |
| Folder filter column | ✅ committed (`dac06254`) | icon box 24→36 / menu 24→32 (asset box sizes); rest already matched |
| Chat top bar | ✅ ported, verifying | avatar Y −1, title/status placed at fixed Y=8/28 (Stack, was drifting centered Column), title right-gap 3px; rest already faithful (`_ChatTopBar` @ chat_view.dart:6393) |
| Shell / 3-column | ⬜ pending | looked correct in screenshots; likely low-deviation (constants 260/540/380/292/392, min 380×480) |
| Chat list panel (search/tabs) | ⬜ pending | |
| Message bubble TAIL | ✅ ported (this session) | Replaced the hand-drawn bezier `_BubbleTailBorder` (8px wide, dropped 5px *below* the bubble — wrong geometry) with AyuGram's **real `bubble_tail` asset** (6×10px) tinted with the bubble bg via `ColorFilter.mode(srcIn)` + h-flipped for outgoing, positioned at the squared bottom sender-side corner — a 1:1 port of `PaintSolidBubble`'s `tail.paint` (ui/chat/message_bubble.cpp). Mask converted to alpha PNG (@1x/2x/3x) under `assets/icons/bubble_tail.png`. Bottom sender corner already squared (`bottomSenderSide==0` when showTail). Radii confirmed exact: large=16px, small=`roundRadiusLarge`=6px. |
| Message bubble frame+text | ✅ frame faithful | ALL frame metrics confirmed exact vs `ui/chat/chat.style`: `msgPadding 11/8/11/8` == Dart `EdgeInsets.symmetric(h:11,v:8)`; `msgMaxWidth 430px`; `msgDateFont 13px`; radii 16/6; corner-grouping; 2px shadow; tail (this campaign). Incoming-group content (sender colors/avatars/reactions) renders in real groups (verified گروه Mahsa Net). |
| Media message types | ⬜ pending | photo/video/gif/file/voice/sticker/location/contact indicators in message_bubble.dart — verify each against real messages |
| Message list (scroll/sep/FAB) | ⬜ pending | date separators, unread divider, scroll-to-bottom FAB, inter-message spacing |
| Compose area | ✅ layout faithful | order confirmed 1:1 vs `ComposeControls::updateControlsGeometry` (compose_controls.cpp:3577): attach/comments LEFT of field; ttl/scheduled/silent/emoji/send stacked on the RIGHT (emoji just left of send). The "AI" button = real translate/AI-editor feature gated by `showAiEditorButton`, not a placeholder. |

## Method
- Each component → one focused agent reads the AyuGram C++ + current Dart, fixes
  concrete deviations only (no wholesale rewrites), preserves the data-binding /
  public API so the app keeps building. Parent (main loop) builds + screenshots +
  commits per component.
- Monoliths (`chat_view.dart` 22k, `message_bubble.dart` 11k) are edited in place
  for targeted fixes; a full split into `ui/chat/*` folders is deferred until the
  higher-value bubble re-port needs it (the `_BubbleTailBorder` R1 rewrite can be
  done surgically in place — it's isolated at message_bubble.dart:84-167).

## ✅ BIG "BUGGY" FIX — forum topics rendered blank (FIXED, commit 28b53504)
The real content chats rendered **blank**. Root cause (confirmed via DB): they are
**forum topics** (engine DB `type=4`), stored with the *topic id* as `chat_id`
(1, 6, 10, 149154…). Opening one passed that bare id to the read path; the core's
`resolvePeer()` saw a positive id → `PeerUser` → `InputPeerUser{id,hash:0}` →
Telegram `PEER_ID_INVALID`, so ~68 chats showed empty. Each topic row already kept
its parent forum in `parent_id` (e.g. عمومی = topic 1 of forum `-1001796213998`),
and the SEND path was already topic-aware (`TopMsgID`) — only READS weren't.

Fix routes topic reads through the parent forum + topic thread
(`MessagesGetReplies(parent, MsgID=topic)`), with `GetTopicPinnedMessages` and
parent-routed online/peer-settings. `cores/base.go` (+ThreadID),
`cores/telegram.go`, `engine/cache_msgs.go` (topicRoute), `engine/cache_users.go`.
Verified: عمومی + Musics (different forums) each load 30 messages, zero
PEER_ID_INVALID, desktop + mobile — sender names/avatars/reactions/reply-quotes/
pinned bar all render. **This unblocks incoming-group-bubble fidelity work.**

Residual (pre-existing, non-blocking): rapid topic-switching can transiently
`CHANNEL_INVALID` on GetOnlineCount/GetPeerBarSettings (parent access-hash warmup;
also hits unmodified GetScheduledMessages). Does NOT blank the chat.

## Verified-working this session
- App launches clean after the Phase-0 de-hack (new plugins init fine, zero log errors).
- Auth session loads; chat list, folders, unread badges, selected/active row, top bar,
  compose bar, and outgoing text bubbles all render correctly.

## Session 1 result (overnight run)
Committed: Phase 0 de-hack (`a89c070c`, pushed) + chat list row & filter (`dac06254`)
+ chat-view/dialogs chrome — top bar, compose, chat list panel (`9da73867`); shell
verified accurate (no change). The entire chat-list + chat-view **chrome** is now
ported 1:1 to AyuGram and screenshot-verified.

NOT done (blocked / deferred — deliberately NOT attempted unattended):
- **Message CONTENT fidelity** (bubble frame/tail, media types, message list): the
  incoming-group rendering (sender-name colors, member avatars, reactions — the
  actual pain area) can't be visually verified because the real group chats fail to
  load (`PEER_ID_INVALID`, see above). The recently-fixed group-chat rendering
  works; I did NOT risk unverifiable tweaks to it. Verify with a chat that loads,
  then port.
- **Monolith split** (chat_view/message_bubble → ui/chat/* folders): a big but
  mechanical refactor; context-heavy — do it in a focused session before the bubble
  re-port. `_BubbleTailBorder` (the R1 tail) is isolated at message_bubble.dart:84
  and can be rewritten surgically without the full split.
- **Backend `PEER_ID_INVALID`**: the highest-impact "bug" (real chats blank) —
  investigate peer access-hash refresh in `go/cores/telegram.go`.
