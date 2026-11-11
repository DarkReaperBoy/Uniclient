# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: GUI rebuild (§6); the READ-POSITION front CLOSED (session 417, one
  atomic): the msg-level unread bars ride the engine's read position — cores
  Dialog carries ReadInboxMaxID/ReadOutboxMaxID (tg extractDialogs fills
  them), the chats table gains read_inbox_max_id (migration V58) with the
  MONOTONIC upsert law (a stale dialog list never regresses it),
  handleReadState advances it on numeric MyLastRead (non-numeric keeps the
  counter-only law), ChatInfo/snapshot/chat_updated/SearchChats carry it;
  app law: Entry.ReadInbox rides the dialogs row (the row IS the live
  read-position projection — no port method, no TOCTOU), openCmdAfterPress
  captures it, ChatLoaded{ReadInbox} stores openReadInbox, FeedItems(msgs,
  readInbox, ...) paints 'Unread messages' on the first !Out message with a
  numeric id beyond the position (0/unknown or non-numeric ids → honestly no
  bar), applyMsgReceived keeps the bar on the first unread, applyChatUpdated
  re-derives the open chat live (a read advance moves or drops the bar,
  ChatDirty re-measure)
- next: the D-1 residuals (hover/over colors + ripple with the skin's
  hover pass; replyReturn jumps) or the next §6.2 capability seam; owner
  redirect wins
- owner-waiting: N-1 — install the uniclient-android APK artifact
  (build 42622715804) on a device and report (android GUI-default check)
- last-gate: session 417 — CI GATE OF RECORD GREEN: Verify 42943763854
  (05cdba03, atomic 1) completed success — all 3 jobs (test/vet/gofmt/
  smoke, nix, cross-builds); Build 42945626236 (4b1d88f3) completed
  success; quick gates GREEN scoped on all three atomics (tests/engine
  6.6s, tests/gui, tests/ui, tests/bootstrap, cores 58s; app/appport/
  window/cmd/renders via windows vet), gofmt + comment ban clean, js/wasm
  full-tree build green; Verify 42945731210 (4b1d88f3, atomic 2) +
  Verify 42946952451 (05e897af, atomic 3) + Build 42946898075 in flight
  at yield — record next session

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| W-1 | ui/app InitialModel | CLOSED 2026-11-09 (session 408): the zero-account scene now paints the frame — dialogs column SurfaceContainerLow vs chat Surface, 54dp header band, the reference-measured search field (7,9,W-18,35 r18) with real focus/typing/backspace/blink; driven live at 1440x900 + 390x844 (pixel scan: pill exact, ring+caret+typed text verified). The residual — the engine-driven add-account affordance — moved to the new front item below | session 408 driven journey | done |
| W-2 | app/engine bridge | CLOSED 2026-11-11 (sessions 410-417): the read-position front (session 417: read_inbox_max_id rides the whole wire — Dialog/DB/ChatInfo/snapshot/chat_updated/SearchChats + the monotonic MAX law; Entry.ReadInbox → ChatLoaded{ReadInbox} → FeedItems bar law + live re-derive on read advance) AND the above-the-fold pagination (session 417 atomic 2: ChatPort.MessagesBefore + the +1 same-ms-inclusive cursor + ID-dedup + the no-progress loop breaker + ChatPrepended{Msgs} re-derives its own items with the one-bar compose law); the search-results sections front CLOSED (session 416); msg_received row bump + payload unification + chat_updated atomic + filter + feeds landed (sessions 410-413) | session 417 gates | done |
| N-1 | android APK | GUI-default on android is runtime-unverifiable in-sandbox (no emulator/device); expected: the empty Material surface, not a black zombie | session 405 (js sibling); js live-verified in 406; APK artifact on build 42622715804 | owner installs the uniclient-android APK artifact and reports |
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build 42597570851 | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | ATOMIC 1 LANDED (session 417): the down-button unread-count badge — 22dp, centered x, top 0 (jump_down_button.cpp paintEvent + historyToDownBadge*); Model.openUnread rides the row (captured at open, live via chat_updated), pane.DownBadgeText projects FormatUnreadCounter, the painter paints the pill (Primary/OnPrimary, the dialogs badge skin law) over the button; hover/over colors + ripple deferred: no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |
| D-3 | build.yml web job | CLOSED 2026-11-10 (session 414, two atomics — see the session entry for the evidence trail) | gotd = 0 packages in the js link graph; wasm plain build 32,837,371 -> 26,714,844 B (-6,122,527 B, -18.6%); <20MB projection did not hold — remaining bulk = web trio deps (mautrix+goolm, bale gRPC-web, pion webrtc) + the rebuilt GUI (gio+fonts) | done; CI web job ships the trimmed wasm from the atomic-2 push |
| D-4 | window keys | ATOMIC 2 LANDED (session 413): plain Enter/Return -> ChatComposeSubmitted -> composeSubmittedCmd (guards: open+port+CanSend+non-empty) clears the field and fires ChatPort.Send -> ChatComposeSendRequested{OK,Text}; failed sends restore the field (composeEdit — no data loss); Up/Down arrows = ChatScrolled step 20dp, PageUp/PageDown = 200dp (tokens ScrollKeyStep = WheelNotch/WheelScrollLines/WheelPixelToAngleDelta, ScrollKeyPageStep = 10x — the Qt qabstractslider defaults through the wheel law); CanSend lands on the open transition from the row type (channels read-only — honest default until the writability front carries admin rights); REAL-seam: appport.Send -> engine.SendMessage -> optimistic msg_received -> open-chat append (wire test). Residuals: Up-on-empty-field edit-last rides the messages/edit front (scrolls meanwhile), Ctrl+Up/Down reply-cycle rides the reply front, scroll keys need compose focus — the unfocused chat pane has no key routing yet (window front) | history_widget.cpp 9276-9349 (fetched 2026-11-09) + qabstractslider defaults | IME ranged EditEvents + SelectionCmd/SnippetCmd contract = the mobile/IME front; window-front key routing |

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
