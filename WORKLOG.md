# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: GUI rebuild (§6); the engine-driven add-account affordance (W-1's
  residual — the product is unusable without it; every §4 live drive is
  BLOCKED-env on "no add-account surface"): the main-menu drawer first
  (reference-measured), then the Add Account button + backend picker + the
  port/engine wire, then the auth surface (StartAuth/SubmitAuthInput)
- next: session 419 atomic 1 — the main-menu surface (toggle+panel+scrim+
  open/close+account rows+cover/footer, hover/ripple skin on the toggle)
- owner-waiting: N-1 — install the uniclient-android APK artifact
  (build 42622715804) on a device and report (android GUI-default check)
- last-gate: session 418 CI GATE OF RECORD GREEN — Verify 42971364147
  (head 35354292) all 3 jobs success (Test&vet&gofmt&smoke / Cross-builds
  windows+js / Nix flake; only the tag-match step skipped by design), Build
  42971351623 success, pages build 42971527859 success

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| W-1 | ui/app InitialModel | CLOSED 2026-11-09 (session 408): the zero-account scene now paints the frame — dialogs column SurfaceContainerLow vs chat Surface, 54dp header band, the reference-measured search field (7,9,W-18,35 r18) with real focus/typing/backspace/blink; driven live at 1440x900 + 390x844 (pixel scan: pill exact, ring+caret+typed text verified). The residual — the engine-driven add-account affordance — moved to the new front item below | session 408 driven journey | done |
| W-2 | app/engine bridge | CLOSED 2026-11-11 (sessions 410-417): the read-position front (session 417: read_inbox_max_id rides the whole wire — Dialog/DB/ChatInfo/snapshot/chat_updated/SearchChats + the monotonic MAX law; Entry.ReadInbox → ChatLoaded{ReadInbox} → FeedItems bar law + live re-derive on read advance) AND the above-the-fold pagination (session 417 atomic 2: ChatPort.MessagesBefore + the +1 same-ms-inclusive cursor + ID-dedup + the no-progress loop breaker + ChatPrepended{Msgs} re-derives its own items with the one-bar compose law); the search-results sections front CLOSED (session 416); msg_received row bump + payload unification + chat_updated atomic + filter + feeds landed (sessions 410-413) | session 417 gates | done |
| N-1 | android APK | GUI-default on android is runtime-unverifiable in-sandbox (no emulator/device); expected: the empty Material surface, not a black zombie | session 405 (js sibling); js live-verified in 406; APK artifact on build 42622715804 | owner installs the uniclient-android APK artifact and reports |
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build 42597570851 | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | hover/over + ripple LANDED everywhere the skin has TwoIconButton sites (session 418 atomics 1+3: all three chat corner buttons AND the dialogs to-up button paint Material state layers + the reference ripple law; see the session entry for the wire); the ripple primitives live in ui/tokens | jump_down_button.cpp 41-67 (dev HEAD), corner_buttons.cpp 300-306, lib_ui ripple_animation.cpp, widgets.style defaultRippleAnimation, chat_helpers.style 1207-1222, dialogs.style dialogsMenuToggle 284-296 | residuals: replyReturn branch of downClick + loadedAtBottom==false state return ride the reply/pagination fronts |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |
| D-3 | build.yml web job | CLOSED 2026-11-10 (session 414, two atomics — see the session entry for the evidence trail) | gotd = 0 packages in the js link graph; wasm plain build 32,837,371 -> 26,714,844 B (-6,122,527 B, -18.6%); <20MB projection did not hold — remaining bulk = web trio deps (mautrix+goolm, bale gRPC-web, pion webrtc) + the rebuilt GUI (gio+fonts) | done; CI web job ships the trimmed wasm from the atomic-2 push |
| D-4 | window keys | ATOMIC 2 LANDED (session 413): plain Enter/Return -> ChatComposeSubmitted -> composeSubmittedCmd (guards: open+port+CanSend+non-empty) clears the field and fires ChatPort.Send -> ChatComposeSendRequested{OK,Text}; failed sends restore the field (composeEdit — no data loss); Up/Down arrows = ChatScrolled step 20dp, PageUp/PageDown = 200dp (tokens ScrollKeyStep = WheelNotch/WheelScrollLines/WheelPixelToAngleDelta, ScrollKeyPageStep = 10x — the Qt qabstractslider defaults through the wheel law); CanSend lands on the open transition from the row type (channels read-only — honest default until the writability front carries admin rights); REAL-seam: appport.Send -> engine.SendMessage -> optimistic msg_received -> open-chat append (wire test). Residuals: Up-on-empty-field edit-last rides the messages/edit front (scrolls meanwhile), Ctrl+Up/Down reply-cycle rides the reply front, scroll keys need compose focus — the unfocused chat pane has no key routing yet (window front) | history_widget.cpp 9276-9349 (fetched 2026-11-09) + qabstractslider defaults | IME ranged EditEvents + SelectionCmd/SnippetCmd contract = the mobile/IME front; window-front key routing |

## Session 418 — the skin's hover+ripple machinery: chat corner buttons (2026-11-11)

- Boot: fresh-sandbox recovery — repo re-cloned (remote URL kept token-free),
  Go 1.27.1 re-installed per scripts/env.sh (toolchain + module cache
  refilled), token in .env (never printed, gitignored), identity
  agent@uniclient; sync clean (main == origin at 885b4e61); CI green at
  head (Verify 42946952451 + Build 42946898075 + pages serving).
- Reference mined FIRST (§1.17), in-session: jump_down_button.cpp dev HEAD
  41-67 (over||down → over icon variants, paintRipple between below/above
  layers, EllipseMask(42) — the ripple area IS the painted circle:
  rippleAreaPosition(5,15) == HistoryToDownCircleX/Y, rippleAreaSize 42 ==
  CircleSize); corner_buttons.cpp 300-306 (downClick: Ctrl||!replyReturn →
  UnreadMessagePosition else replyReturn — the replyReturn branch rides
  the reply front, not this atomic); lib_ui ripple_animation.cpp (radius 0→
  farthest-corner of the mask box, show easeOutQuint, release → linear
  opacity fade while the radius keeps growing, add()/lastStop/clearState
  lifecycle); widgets.style 703-707 (defaultRippleAnimation show 650ms hide
  200ms); chat_helpers.style 1207-1222 (TwoIconButton 52x62, ripple area
  law). Skin law (§6): Material state layers own the colors — hover 8%,
  ripple 12% (M3 interaction states), OnPrimaryContainer over the
  PrimaryContainer circle.
- Atomic 1 (ONE change — hover + ripple on all three chat corner buttons):
  TOKENS — HistoryToDownRippleShowMs 650 / HideMs 200 (the reference pins),
  StateLayerHoverAlpha 0.08 / StateLayerRippleAlpha 0.12 (the Material
  pins). HISTORY — Ripple/RippleState/RippleMaxRadius/RippleView
  (easeOutQuint, radius = round(max*shown), alpha linear fade) +
  ChatPane gains per-button Down/Mentions/Reactions Hover+Ripple fields.
  APP — ChatCorner enum + ChatRippleState (Button + history.RippleState);
  Model.ChatHover/ChatRipple; dragChat updates hover from every mouse
  move/drag (ChatDragged carries Touch — touch never hovers; window.go
  sources e.Source), chatCornerAt hit order reactions>mentions>down (the
  paint order's mirror); pressChat starts the ripple at the press point in
  circle-box coords on each corner branch; releaseChat fades it on
  release-in-or-out (chatRippleRelease — the reference lastStop law);
  ChatPressCanceled clears instantly (clearState); ChatTick advances
  chatRippleTick (fade-end clear); ChatLoaded resets both; ChatLeft (new
  msg, window.go routes pointer.Leave — gio delivers Leave to the chat
  input area on cursor exit) clears hover; ChatRippleActive joins the
  window tick/Invalidate conditions. VIEW — hover bools per button +
  RippleView projection per the ripple's owning button. PAINTER —
  paintCornerFeedback: the 42dp circle ellipse mask, hover fill
  OnPrimaryContainer@8%, ripple ellipse at origin radius r@
  12%*alpha nested under the mask (the reference's mask law — the ripple
  never spills outside the round button), painted between the circle and
  the arrow/glyph/badge (the reference's below/above layer order).
  red->green: tests/ui/history_corner_hover_test.go (token pins 650/200/
  0.08/0.12; RippleMaxRadius corner 59 / center 30 / outside 74 / (9,17) 41;
  easeOutQuint show 20@130ms→29@half→30@end; fade linear 1→0.5@100ms→0
  @200ms with radius still growing 25→29→30) + tests/gui/
  app_corner_hover_test.go journeys (hover set/move-clear via mouse
  ChatDragged, touch-move never hovers, ChatLeft clears; press → origin
  (9,17) radius 0 alpha 1 + ChatRippleActive; mid-show radius>0;
  release → mid-fade alpha ∈ (0,1) → fade-end clear; release-outside still
  fades without the click jump; cancel clears; press off-button no ripple;
  mentions-button ripple owns its pane slot only; chat switch resets
  hover+ripple; paint journey PaintChatPane with hover+growing ripple).
- Gates: quick gate GREEN scoped (tests/engine 6.8s, tests/gui, tests/ui;
  app/appport/dialogs-render/history-render/window/cmd via windows vet),
  gofmt clean, comment ban clean (391 files), js/wasm full-tree build
  green. §4 live pixel drive BLOCKED-env (needs an account; no add-account
  surface yet) — same class as session 417; journeys drive the real
  press→ripple→release seam through Update/View.

- Atomic 2 (pure refactor, the enabler for the dialogs adoption): the ripple
  primitives moved from ui/history to ui/tokens — Ripple/RippleState/
  RippleMaxRadius/RippleView/easeOutQuint live with the other pinned skin
  laws (the durations are the reference pins, the state-layer alphas the
  Material pins, the math is table law); history/dialogs both already
  import tokens so no new dependency edge; ChatPane/App/painter references
  migrated mechanically (history.Ripple* -> tokens.Ripple*), the pins moved
  tests/ui/history_corner_hover_test.go -> tests/ui/tokens_ripple_test.go
  unchanged in value. quick gate GREEN scoped; gofmt + comment ban clean;
  js/wasm full-tree build green.

- Atomic 3 (the dialogs to-up button adopts the machinery — D-1's residual
  site, same skin law): MODEL — DialogsHover bool + DialogsRipple
  tokens.RippleState; DialogsDragged carries Touch (window.go sources
  e.Source — touch never hovers), dragDialogs drives hover from every mouse
  move/drag via dialogsToUpHitAt; pressDialogs' to-up branch starts the
  ripple at the press point in circle-box coords; releaseDialogs fades on
  release-in-or-out; DialogsPressCanceled clears instantly;
  dialogsRippleTick rides DialogsTick (fade-end clear);
  DialogsRippleActive joins the window tick/Invalidate conditions;
  DialogsLeft (new msg; routeInput's filter gains pointer.Leave — gio
  delivers Leave to the dialogs tag when the cursor leaves the dialogs
  hit region, including into the chat pane) clears hover; View projects
  ToUpHover + ToUpRipple gated on the active state (a zero RippleState is
  not a no-op — RippleView(zero) is a full ripple). PANE — dialogs.Pane
  gains ToUpHover/ToUpRipple. PAINTER — paintToUpFeedback: the circle
  ellipse mask, hover fill OnPrimaryContainer@8%, ripple ellipse@
  12%*alpha nested under the mask, painted between circle and arrow (a
  local withAlpha joins the painter's local helpers). red->green:
  tests/gui/dialogs_to_up_hover_test.go (hover set/clear via mouse
  DialogsDragged, touch never hovers, DialogsLeft clears; press → origin
  (21,9) radius 0 alpha 1 + DialogsRippleActive; mid-show; release →
  mid-fade → fade-end clear; release-outside still fades without the jump;
  cancel clears; press off-button no ripple; paint journey PaintPane with
  hover+ripple). quick gate GREEN scoped; gofmt + comment ban clean;
  js/wasm full-tree build green.

## Session 417 — the read-position front: the unread bars ride the engine's read position (2026-11-11)

- Boot: fresh-sandbox recovery — repo re-cloned, Go 1.27.1 re-installed per
  scripts/env.sh (toolchain + module cache refilled), token in .env (never
  printed, gitignored), remote URL kept token-free, identity agent@uniclient;
  sync clean (main == origin at 1bb55445).
- Atomic 1 (ONE change — the complete read-position vertical seam, W-2's
  msg-level unread-bar residual): CORES — Dialog gains
  ReadInboxMaxID/ReadOutboxMaxID, telegram extractDialogs fills them from
  tg.Dialog. ENGINE — chats table gains read_inbox_max_id (CREATE +
  migration V58), UpsertChat INSERT + the monotonic conflict law
  (MAX(excluded, chats) — a stale dialog list can never regress a read
  position), GetUnifiedChatList/GetChatList/SearchChats SELECTs + scanChats
  + emitChatUpdate carry it (ChatInfo json read_inbox_max_id);
  handleReadState: numeric MyLastRead advances the position monotonically
  and clears the counter; non-numeric keeps the old counter-only law
  exactly (the existing test's pin). APP — snapshotChat/snapshotRow map it
  to Entry.ReadInbox (the dialogs row IS the live read-position
  projection: chat_updated keeps it fresh, so the open seam reads it from
  the pressed row — no new port method, no TOCTOU); openCmdAfterPress
  captures row.ReadInbox into ChatLoaded{ReadInbox}; Model.openReadInbox;
  FeedItems(msgs, readInbox, now, group) marks the FIRST !Out message with
  numeric id > position with UnreadBarText ('Unread messages' — the app
  owns user strings; geometry was already token-pinned, the seam was the
  gap: painting existed, data never reached it); position 0 or non-numeric
  ids → honestly no bar (never a false all-unread lie on cores that don't
  report positions); applyMsgReceived passes openReadInbox (new messages
  below never steal the bar); applyChatUpdated → applyOpenReadPosition:
  open chat + loaded + changed position → re-derive items (bar moves
  down or drops when reads land), Heights/Hits invalidated, ChatDirty
  re-measure. red->green: engine tests/engine/readpos_test.go (snapshot
  JSON + all three list paths carry it; numeric advance + stale-dialog
  MAX-no-regress + monotonic-never-regress; non-numeric law; the port-level
  wire: seeded msgs + FeedItems bar placement + fully-read/unknown no-bar;
  outgoing/non-numeric skip; the row rides snapshot + advanced
  chat_updated); gui tests/gui/app_unread_bar_test.go journeys (press ->
  open -> bar on first unread only + pane projection after measure;
  fully-read/unknown no bar; outgoing/non-numeric skip; read-advance
  replaces the bar + dirty re-measure; read-advance moves the bar down;
  msg_received keeps the bar on the first unread; chat switch resets).
  §4 evidence: the journeys drive the app model through the real press->
  open seam + the engine wire test drives the real engine -> port ->
  FeedItems seam; live pixel drive BLOCKED-env (needs an account; no
  add-account surface yet) — the bar's geometry/paint was already pinned
  (tests/ui history_entry_test.go UnreadBarGeometry/metrics + painter
  source pin), the data seam is the closure.
- Gates: quick gate GREEN scoped (tests/engine 6.6s, tests/gui, tests/ui,
  tests/bootstrap, cores 58s native; app/appport/dialogs-render/
  history-render/window/cmd via windows vet), gofmt clean, comment ban
  clean (385 files), js/wasm full-tree build green. Existing suites all
  green (app_feeds/app_chat_wire updated mechanically for the FeedItems
  signature).

- Atomic 2 (the LAST W-2 residual — ChatPreloadTopRequested was a no-op:
  the armed request fetched nothing, and MoreAbove was never true in the
  real flow): ChatPort gains MessagesBefore(accountID, chatID, beforeMs,
  limit) — appport rides GetMessages's beforeMs branch, one shared
  wireMessages mapper (chronological, same reverse-once law as Messages);
  the cursor law: beforeMs = oldest-loaded ts + 1 (the engine's strict `<`
  becomes same-ms-inclusive — telegram's second-granularity timestamps make
  same-second siblings common; the boundary message rides the page and the
  app DEDUPS by loaded msg-ID — no skips, no duplicates); openCmdAfterPress
  sets MoreAbove from the full-page cursor (len == chatHistoryLimit);
  ChatPreloadTopRequested → chatPreloadTopCmd (guards: port + open + loaded
  + MoreAbove + non-empty window; the fetch + dedup live in the Cmd —
  engine-owned timing) → ChatPrepended{Msgs, MoreAbove, Now}; the loop
  breaker: MoreAbove = full page AND fresh > 0 (an all-duplicate page
  closes the cursor — termination proven); ChatPrepended re-derives the
  page's OWN items via FeedItems (the page owns date dividers/attachment
  inside itself; the cross-page attachment/divider seam is the known
  pre-existing residual riding the messages/edit front) with the ONE-BAR
  compose law: a page carrying an unread bar clears the existing items'
  bars first (the older first-unread is THE first unread — never two bars);
  chatMsgs grows prepend-only (window pruning rides a future front).
  red->green: tests/engine/messages_before_test.go (120-msg history: newest
  50 -> older 50 ids 22..71 with the boundary inclusive -> final 22 ->
  strict-below-oldest empty; chronological order + unknown chat ok-empty);
  tests/gui/app_preload_wire_test.go journeys (open carries the full-page
  cursor; request → cmd fetch → ChatPrepended with beforeMs == oldest+1,
  items 60, cursor closed on short page, full page keeps it; boundary msg
  deduped; all-duplicate page terminates; gates: no-cursor/no-port never
  fetch; the bar moves to the older page's first unread with exactly one
  bar total). Existing ChatPrepended constructors migrated mechanically
  (preload/mentions/reactions/scroll-date + the three port fakes gain
  MessagesBefore).
- Gates (atomic 2): quick gate GREEN scoped (tests/engine 6.6s, tests/gui
  0.04s, tests/ui, tests/bootstrap 0.9s; app/appport/window/cmd/renders
  via windows vet), gofmt clean, comment ban clean (387 files), js/wasm
  full-tree build green.

- Atomic 3 (D-1's badge — the down-button unread-count counter): the
  badge's data path rides the SAME row law as the read position —
  Model.openUnread captured from the pressed row (row.Unread) at open,
  ChatLoaded{Unread} stores it, applyOpenChatRow (the renamed
  applyOpenReadPosition, now tracking the whole open row) keeps it live
  via chat_updated (a read advance clears the count — the badge vanishes);
  View projects pane.DownBadgeText via tokens.FormatUnreadCounter (the
  app owns user strings; visibility rides the button's own DownProgress
  gate in the painter — no badge without the button); geometry:
  history.DownBadgeGeometry(button, textWidth) — 22dp (the reference
  historyToDownBadge law), centered on the button's x, top 0 of the
  button, pill width = max(22, text + 2*5) radius 11 (the dialogs badge
  sizing family); the painter gains fontBold + paints the pill in
  Primary/OnPrimary (the dialogs counter skin law — one badge color
  across the skin; hover/over colors + ripple stay D-1-deferred).
  red->green: tests/ui/history_down_badge_test.go (token pin 22 +
  centered/top-0/min-width/wide-centered geometry) + tests/gui/
  app_down_badge_test.go journeys (open carries 7; persists while
  scrolled; zero unread → empty; read advance clears; paint journey with
  the visible button records the badge; chat switch resets).

## Session 416 — search-results sections: the global-search wire + presentation (2026-11-11)

- Four atomics (full detail in git): (1) the global-search wire — engine
  SearchGlobalChats carries Username, no local fallback on core error, the
  SearchChats 3-column scan BUG fixed, ChatPort.SearchGlobalChats, the app
  debounce/pending/stale-drop/'@'-mode law; (2) the 28dp searched-bar
  presentation + global rows stitched into List/Pane/painter with the
  stitched selection law; (3) PaintComposeBar's caller (the W-2 zero-caller
  seam — paintChatBody restructure); (4) the search-EMPTY state ('No
  Results', the 32-rune preview cap, the 220dp band). Gates: quick gates
  GREEN scoped; Verify 42882442032 (2aeebcc4) completed success at job AND
  step level; builds on every intermediate head green or concurrency-
  cancelled (superseded, not red).
