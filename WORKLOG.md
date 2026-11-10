# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: GUI rebuild (§6); W-2 chat_updated atomic landed (session 412):
  full-payload chat_updated events drive live dialogs-row updates — the
  ONE snapshotRow mapping path, replace-or-insert per account
  (copy-on-write), the engine list law re-derived locally (is_pinned
  DESC, last_msg_time DESC — GetChatList ORDER BY; stable ties keep wire
  order, message-less rows bottom; Entry.SortTime), snapshot-equivalence
  pinned; the active filter + identity selection re-apply (selection
  follows a moved row); bare-map legacy payloads (JoinChannel/
  DeleteChatHistory) drop until the engine-side unification atomic.
  next front work: msg_received row bump for non-open chats, then D-4
  atomic 2, then D-3
- next: msg_received rows, engine payload unification, D-4 atomic 2, D-3
- owner-waiting: N-1 — install the uniclient-android APK artifact
  (build 42622715804) on a device and report (android GUI-default check)
- last-gate: session 412 — quick gate GREEN (native vet+test scoped —
  tests/engine 6.7s, tests/gui, tests/ui, ui/dialogs, ui/history;
  windows vet gio legs), gofmt + comment ban clean (370 files), js/wasm
  32,837,371 B builds green; BLOCKED-env driven rows (no backend in the
  sandbox — the seam proven at the engine boundary: real HandleUpdate
  JSON -> real chat_updated bytes -> app rows); gotd windows cross-build
  compile OOM = documented §9 rung-7 machine limit, CI verify is the
  gate; CI dispatch on this push follows (record next session).

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| W-1 | ui/app InitialModel | CLOSED 2026-11-09 (session 408): the zero-account scene now paints the frame — dialogs column SurfaceContainerLow vs chat Surface, 54dp header band, the reference-measured search field (7,9,W-18,35 r18) with real focus/typing/backspace/blink; driven live at 1440x900 + 390x844 (pixel scan: pill exact, ring+caret+typed text verified). The residual — the engine-driven add-account affordance — moved to the new front item below | session 408 driven journey | done |
| W-2 | app/engine bridge | PART: chat_updated atomic landed (session 412 — full-payload chat_updated drives live row content: ONE snapshotRow mapping path, replace-or-insert into accountRows, engine list law sorted locally (pinned DESC, last_msg_time DESC), filter+identity-selection reapplied, snapshot-equivalence pinned; legacy bare-map payloads (JoinChannel/DeleteChatHistory) drop — engine-side unification open); filter atomic landed (session 411 — typed search filters the rows: mined reference law SearchWords/MatchesWords in ui/dialogs/search.go, word-prefix + accent/case fold + AND, garbage query = full list; selection = row identity across filter cycles, restore-on-clear, data-gone clears); feeds atomic landed (session 410); STILL OPEN: PaintComposeBar zero callers, msg_received for a non-open chat never bumps its row (preview/date/unread/move), msg-level unread bars need read-position, ChatPreloadTopRequested is a no-op, transliteration/username/"@"-mentions matching + the search-results sections ride the search front | session 412 wire + law tests | msg_received row bump + engine payload unification; then D-4 atomic 2 |
| N-1 | android APK | GUI-default on android is runtime-unverifiable in-sandbox (no emulator/device); expected: the empty Material surface, not a black zombie | session 405 (js sibling); js live-verified in 406; APK artifact on build 42622715804 | owner installs the uniclient-android APK artifact and reports |
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build 42597570851 | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |
| D-3 | build.yml web job | wasm size diet: the js/wasm build ships every core incl. the six raw-TCP backends that can never connect from a browser (§7 web truth) — build-tag exclusion at the engine factory projected <20 MB; also headroom under git's 100 MB file ceiling on gh-pages | headless-host wasm = 31,162,944 B after the keyboard atomic (v0.9.1's old-GUI build was 88,659,256 B) | one atomic with tests: bootstrap factory js variant + per-core js stubs |
| D-4 | window keys — atomic 2 | Enter=submit (ShouldSubmit law: default Enter-mode = plain Enter/Return submits, Shift/Ctrl+Return newline — already mapped) -> ChatComposeSubmitted + send-request seam (ChatBottomRequested-pattern) + field clear; Up/Down/PageUp/PageDown = history scroll (never compose cursor moves — customUpDown law); Up on EMPTY field + canWrite + !edit + !reply -> edit last editable message, else scroll; Ctrl+Up/Down -> reply prev/next (reply front) | AyuGramDesktop dev history_widget.cpp 9276-9349 (fetched 2026-11-09): Down always _scroll->keyPressEvent; Up scrolls unless field empty && canWrite && !_editMsgId && !_replyTo, then lastEditableMessage() -> editMessage else scroll; PageUp/PageDown always scroll; Enter -> ShouldSubmit(sendSubmitWay, mods); Qt key scroll = SliderSingleStep/PageStep (qabstractscrollarea.cpp 1215-1220; qabstractslider.cpp 180: defaults singleStep 1 pageStep 10 — but our own wheel law 120-angle notch = 60px = WheelScrollLines 3 => singleStep = 20px = WheelNotchAngleDelta/WheelScrollLines/WheelPixelToAngleDelta); IME ranged EditEvents + SelectionCmd/SnippetCmd contract = the mobile/IME front | atomic 2: ChatComposeSubmitted + ChatComposeSendRequested + scroll keys with the 20px singleStep law; edit-last rides the messages/edit front |

## Session 412 — W-2 the chat_updated atomic: live row content updates (2026-11-10)

- Boot: sandbox recycled — toolchain + module/build caches survived under
  ../toolchain (env.sh re-sourced, go 1.27.1), .env re-created from the
  owner token (gitignored, askpass push intact); no red gate — Build #12
  + Verify #410 green on e627f27a.
- The law: engine emits chat_updated with the full row (emitChatUpdate
  re-reads the chat after read-state/mute/pin/title/… changes) -> the UI
  row must update LIVE. applyChatUpdated: decode {chat}; guards —
  ChatID=="" drops (covers the bare-map payloads JoinChannel/
  DeleteChatHistory still emit — engine-side unification is its own
  atomic), account must already have a snapshot row-set (never fabricate
  a partial list; the snapshot always precedes); row built through the
  ONE snapshotRow path (zero drift snapshot vs update); replace-or-insert
  into a copied slice (copy-on-write storeAccountRows, shared with the
  snapshot path); sortDialogRows re-derives the engine's own list law
  locally (is_pinned DESC, last_msg_time DESC — cache_chats.go
  GetChatList ORDER BY; stable sort: equal-time ties keep wire order,
  message-less rows SortTime 0 bottom) so the post-update store == the
  fresh-snapshot store; Entry.SortTime added (dialogs.Entry) — the UI
  never trusts wire order; reprojectDialogRows re-applies the active
  filter + identity selection (selection follows a row that moves) +
  scroll clamp.
- Tests red->green: tests/gui/app_feeds_test.go +11 (in-place replace at
  a tie, move-by-list-law, pinned law both directions, insert for an
  unseen chat, drop without a snapshot, 7 dropped shapes incl. the legacy
  bare-map payload, selection follows the moved row, filter re-applies on
  a rename + clear restores, snapshot-equivalence invariant, badge fields
  map from the event + non-badge content survives); tests/engine/
  app_chat_wire_test.go +1 REAL-seam (real HandleUpdate read-state JSON
  -> real chat_updated bytes -> app rows: unread 5 -> 0 while mention/
  reaction/mark PERSIST — the real engine tracks them apart from read
  state — rest of the row intact). All existing suites green, zero
  re-pins.
- Edit-tool landmine (sessions 410/411 pattern) hit again: whole-file
  tab->space rewrite — caught by the gate gofmt check, restored canonical
  via gofmt -w (diff back to pure additions; subsequent edits verified
  with gofmt -l in the gate).
- Driven: BLOCKED-env for live rows (no backend in the sandbox — zero
  accounts on the driven path; seam proven at the engine boundary
  instead, session-410 precedent). js/wasm builds green: 32,837,371 B
  (+660,516 B vs session 411: the router case + sort law + tests).
- Gates: quick gate GREEN (native vet+test scoped — tests/engine 6.7s,
  tests/gui, tests/ui, ui/dialogs, ui/history; windows vet gio legs),
  gofmt + comment ban clean (370 files); gotd windows cross-build
  compile OOM = documented §9 rung-7 machine limit — CI verify dispatch
  is the gate; CI record lands next session.
- Next: msg_received row bump for non-open chats, engine chat_updated
  payload unification, D-4 atomic 2, D-3.

## Session 411 — W-2 the filter atomic: typing filters the dialogs rows (2026-11-10)

- Boot: sandbox recycled to zero — toolchain rebuilt per env.sh (go 1.27.1,
  module cache refilled ~1.2G), .env re-created from the owner token
  (gitignored, askpass push intact); no red gate — Build #11 + Verify #409
  green on 4b3f0906.
- The filter law MINED from the reference source (§1.17, live blobs via the
  git API — raw caches proved stale): dialogs_inner_widget.cpp 4408-4417
  applySearchState (query -> PrepareSearchWords; empty words -> clearFilter
  = the full list) + 4475-4481 refreshFilterResults (list->filtered(words));
  dialogs_indexed_list.cpp IndexedList::filtered (every query word must be
  a startsWith PREFIX of some name word, AND across words, never a
  mid-word substring); lib_ui text_entity.cpp 1499-1519 PrepareSearchWords
  (RemoveAccents(trimmed().toLower()), split on the set [\@\s\-\+\(\)\[\]\{\}\
  <\>\,\.\:\!\_\;\"\'\x0], skip empties — fetched at the PINNED submodule sha
  42c6f1e8) + data_peer.cpp fillNames 1080-1130 (name words normalized
  identically). Go port: ui/dialogs/search.go — SearchWords (accent fold
  via x/text NFD+Mn-strip, v0.41.0 promoted indirect->direct, same version)
  + MatchesWords (prefix+AND, empty query matches all).
- App wiring: searchTyped/searchBackspace call reprojectDialogRows;
  setDialogRows unifies the two row stores (accountRows merge, or the new
  dialogFeed for the DialogsLoaded seam) -> filter -> selection law;
  selection = row identity (selectedAccount/selectedChat set at press +
  reprojection): resolves against the VISIBLE rows, hidden-but-alive keeps
  the identity (clearing the filter restores the highlight — reference
  behavior), identity absent from the full rows clears (W-2 data-gone law);
  identityless rows keep the legacy index law when no filter is active
  (TestDialogsElmState pins preserved). Scroll clamp + toUp recheck on
  every reprojection. x/text NFD+Mn-strip folds Latin exactly like the
  reference table; Cyrillic-accent folding is a µ-edge residual.
- Tests: tests/ui/dialogs_search_words_test.go NEW (2 law tables: splitter
  set/NUL/CJK/accent/garbage->empty + prefix/AND/case+accent folds/empty-
  matches-all); tests/gui/app_search_filter_test.go NEW (11: narrows+
  widens, garbage keeps the full list, case+accent folds, selection
  follow+clamp+restore across filter cycles, data-gone clears identity,
  scroll clamp + toUp hide, open journey through a filtered row via the
  port, DialogsLoaded feed path + identityless honest drop, snapshot
  re-applies the active filter, honest empty pane (no prompt when accounts
  exist), paint smoke both shapes). All existing suites green, zero
  re-pins.
- Sandbox note: the Edit tool tab-normalization hit AGAIN (session 410's
  landmine) on elm.go/feed.go whole-file rewrites — restored byte-pristine
  from git both times, every edit redone through a byte-exact python
  patch script; one patch of mine over-unified tabs (2-tab lines -> 1) and
  was rebuilt from the verified exact string.
- Driven (§4, the shell assembled from build.yml verbatim, wasm
  32,176,855 B, agent-browser): 1440x900 — console + page errors EMPTY;
  split intact (64.27% #FEF7FF + 34.21% #F7F2FA + 1.29% pill); click
  (100,27) -> focus ring #6750A4 6.95% of the band; typed 'ma' -> 480 band
  px changed, glyphs 82 px @ x20..71 y24..30, caret follows, placeholder
  gone; backspace x2 -> cleared clean; prompt 'Add an account' 138 px
  centered (976,449) = chat-pane center. 390x844 single-pane — 95.47%
  container + 3.78% pill, ring persists, prompt centered in the list area.
  BLOCKED-env: live-row filtering needs a real backend (zero accounts on
  the driven path — the prompt honestly stays); row semantics proven at
  the engine boundary (wire tests) + the law/app tests. wasm +144,567 B
  vs session 410 (filter paths + x/text norm).
- Gates: quick gate GREEN (native vet+test scoped — tests/engine 6.3s,
  tests/gui, tests/ui, ui/dialogs, ui/history; windows vet for the gio
  cgo legs), gofmt clean, comment ban clean (370 files), js/wasm build
  green.
- Next: chat_updated -> live row updates, D-4 atomic 2, D-3.

## Session 410 — W-2 the feeds atomic: chat data flows through the pump (2026-11-10)

- Boot: sandbox recycled to zero (toolchain + 1.1G module cache survived
  under ../toolchain — env.sh re-sourced, go mod download green); .env
  re-created from the owner token (gitignored, askpass push intact); no red
  gate — Verify #408 + Build #10 green on ea26393e, head 76e623fd was
  doc-only (paths filter skips WORKLOG pushes).
- The feeds atomic (W-2's named next step: chat_snapshot events -> dialogs
  rows + chat rows via the pump): applyEngineEvent became a typed router
  (account_list | chat_snapshot | msg_received); chat_snapshot decodes into
  per-account rows kept in Model.accountRows (copy-on-write map; merged
  projection iterates Accounts in sort order — deterministic; snapshots for
  unknown accounts drop; empty chats clear the account honestly); dialogs
  Entry gained identity (Account, ChatID, Group) so selection survives row
  replacement (Selected follows the same (account, chat) identity, clamps
  to -1 when gone). The open journey: press (mouse or touch-tap) on a new
  selection -> openCmdAfterPress sets Open/openGroup/openLoaded=false and
  returns a Cmd through the new app.ChatPort seam; window.Run wires
  appport.For(eng) (engine.GetMessages -> WireMessage, newest-N window
  reversed to oldest-first — the engine's default DESC order stays
  untouched); the Cmd returns ChatLoaded{Msgs, Items, Now}; Update stores
  the feed (chatMsgs = the open chat's source of truth, Items = pure
  projection) and jumps to bottom through chatJumpBottom consumed in
  ChatMeasured (fresh open always; live append only when at bottom).
  msg_received for the open chat appends through the same FeedItems
  projection (grouping + dividers re-derived from source); other chats
  ignored (their row updates = chat_updated, next atomic). Portless press =
  selection only (no fake open); failed Messages() = nil Cmd (window skips
  nil now) — no fake content.
- Item/date laws MINED from the reference source (§1.17, AyuGramDesktop dev):
  dialogs row date = Ui::FormatDialogsDate (format_values.cpp 526-542 — same
  day OR within 20 h -> HH:MM; else < 7 calendar days -> weekday short
  (langDayOfWeek, lang.strings Mon..Sun); else M/D/YY — QLocale en_US short,
  pinned as the product's English locale); day divider = langDayOfMonthFull
  (lang_keys.cpp: "{month} {day}" full month names, ", {year}" only when
  langDateMaybeWithYear says far (|Δyear|>1, or ±1 year with month gap > 3));
  message grouping = kAttachMessageToPreviousSecondsDelta 900 (history_view_
  element.cpp:107,2439 — same sender, same day, < 900 s, no service/divider
  between; strict <); dialogs preview = lng_dialogs_text_from_wrapped +
  lng_dialogs_text_with_from (lang.strings:5144 — "Sender: text" for
  group/topic rows only); bubble time = locale short time -> pinned HH:MM
  (24 h, matches the existing test pins). FromName only on group incoming.
  Failed send states have no dialogs.SendState slot yet -> hidden (residual).
- Tests: tests/gui/app_feeds_test.go NEW (13: snapshot projection + identity,
  outgoing read SendState, per-account replace + account-order merge +
  unknown-account drop, empty-chats clear, ignored cases (malformed/bad
  data/not-obj/unknown-type/no-payload), selection follow + clamp, open
  journey incl. tall-history bottom jump, nil-port safety, same-row no
  reload, FeedItems grouping/divider/service/day-change/900 s-exact law
  table, msg_received append + attachment recompute + non-open ignore,
  at-bottom append stays at bottom, date-law tables, paint smoke rows +
  items through the real painters); tests/engine/app_chat_wire_test.go NEW
  (4: REAL SyncChats -> captured chat_snapshot JSON -> app.Update -> rows
  (the wire field names proven, not assumed); appport.For -> GetMessages ->
  WireMessage mapping + oldest-first contract; REAL HandleUpdate(new
  message) -> captured msg_received JSON -> app append into the open chat;
  empty chat -> ok, zero messages). Deliberate contract note: the port owns
  the oldest-first order (engine default path stays DESC). All existing
  suites green with zero re-pins.
- Sandbox note: the Edit tool normalized tab-indented Go sources to spaces
  on patch (whole-file rewrites) — caught by gofmt -l + git diff, tree
  restored byte-pristine and the edits redone through a byte-exact patch
  script; core.autocrlf/fileMode now false in the local config.
- Driven (§4, the shell assembled from build.yml verbatim, wasm
  32,032,288 B, agent-browser): console + page errors EMPTY; 1440x900 —
  split intact (64.13% #FEF7FF + 34.62% #F7F2FA + 1.19% #E6E0E9 pill),
  search placeholder 21 px @ 20..58 x 21..30, "Add an account" prompt
  84 px @ 935..1019 x 445..454 center (977,450) = chat-pane center
  exactly; 390x844 single-pane — 96.31% container + 3.46% pill, prompt
  center (195,448) = list-area center (195,449). BLOCKED-env: live rows
  need a real backend (no accounts on the driven path — the login front
  does not exist); the wire is proven at the engine boundary instead
  (real emit -> real JSON -> app decode), CI verify rides along.
- Gates: quick gate GREEN (native vet+test scoped — tests/engine 6.7s,
  tests/gui, tests/ui, dialogs, history; windows vet for the gio cgo
  legs), gofmt clean, comment ban clean (367 files), js/wasm full build
  green. Residuals logged: msg-level unread bars (read-position front),
  MoreAbove pagination (ChatPreloadTopRequested no-op), media messages
  render caption-only until the media front, single-pane open needs the
  route-stack front, chat_updated row updates next atomic. wasm
  +833,272 B vs session 409 (new feed paths).
- Next: filter semantics atomic, chat_updated rows, D-4 atomic 2, D-3.

