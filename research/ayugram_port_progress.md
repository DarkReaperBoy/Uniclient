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
| Message bubble frame+text | ⬜ pending | outgoing bubble already renders well (color/tail/ticks); incoming-group fidelity (sender colors/avatars/reactions) needs real group data to verify — see blocker below |
| Media message types | ⬜ pending | |
| Message list (scroll/sep/FAB) | ⬜ pending | |
| Compose area | ⬜ pending | visible; may have deviations (right-side icon set/order) |

## Method
- Each component → one focused agent reads the AyuGram C++ + current Dart, fixes
  concrete deviations only (no wholesale rewrites), preserves the data-binding /
  public API so the app keeps building. Parent (main loop) builds + screenshots +
  commits per component.
- Monoliths (`chat_view.dart` 22k, `message_bubble.dart` 11k) are edited in place
  for targeted fixes; a full split into `ui/chat/*` folders is deferred until the
  higher-value bubble re-port needs it (the `_BubbleTailBorder` R1 rewrite can be
  done surgically in place — it's isolated at message_bubble.dart:84-167).

## ⚠️ IMPORTANT BACKEND BUG (not UI — flag for review)
Opening the real content chats (the Persian-named groups/channels) renders a
**blank message area**. The log shows the Go engine returning **`PEER_ID_INVALID`
(rpc error 400)** for `GetMessages` / `GetPinnedMessages` / `GetOnlineCount` /
`GetPeerBarSettings` on those peers (e.g. `tele_4beb99fd` peer id resolving to `1`).
This is a **peer access-hash resolution problem in the Telegram core** (stale/missing
access_hash for archived peers), NOT a UI rendering bug — the UI correctly shows
empty because the backend returns nothing. This likely accounts for much of the
"buggy" feel (real chats appear empty). It lives in `go/cores/telegram.go` (peer
resolution / access-hash cache), outside the AyuGram UI-port scope, so it was NOT
touched here. **Recommend investigating peer access-hash caching/refresh next.**

Consequence for verification: the only chats that fetch successfully are the empty
test chats (TestChannel, Test Group Flow) + self-sent messages, so incoming
group-bubble fidelity (sender-name colors, member avatars, reactions) can't be
visually verified right now. Those bubble fixes should be verified once peer
resolution works (or against a chat that does load).

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
