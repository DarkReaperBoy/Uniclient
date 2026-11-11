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
- next: ChatPreloadTopRequested's no-op (the last W-2 residual) or the D-1
  down-button unread-count badge; owner redirect wins
- owner-waiting: N-1 — install the uniclient-android APK artifact
  (build 42622715804) on a device and report (android GUI-default check)
- last-gate: session 417 — quick gate GREEN scoped (tests/engine 6.6s,
  tests/gui, tests/ui, tests/bootstrap, cores 58s native; app/appport/
  dialogs-render/history-render/window/cmd via windows vet), gofmt + comment
  ban clean (385 files); js/wasm full-tree build green; session-416 gates
  stand (Verify 42882442032 GREEN at job AND step level); verify dispatched
  for this push — record the run next session

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| W-1 | ui/app InitialModel | CLOSED 2026-11-09 (session 408): the zero-account scene now paints the frame — dialogs column SurfaceContainerLow vs chat Surface, 54dp header band, the reference-measured search field (7,9,W-18,35 r18) with real focus/typing/backspace/blink; driven live at 1440x900 + 390x844 (pixel scan: pill exact, ring+caret+typed text verified). The residual — the engine-driven add-account affordance — moved to the new front item below | session 408 driven journey | done |
| W-2 | app/engine bridge | PART: the read-position front CLOSED (session 417: read_inbox_max_id rides the whole wire — Dialog/DB/ChatInfo/snapshot/chat_updated/SearchChats + the monotonic MAX law; Entry.ReadInbox → ChatLoaded{ReadInbox} → FeedItems bar law + live re-derive on read advance); the search-results sections front CLOSED (session 416: matching layer 415 + global-search wire + 28dp searched-bar + stitched selection + PaintComposeBar zero-callers + search-EMPTY state); msg_received row bump + payload unification + chat_updated atomic + filter + feeds landed (sessions 410-413) | session 417 gates | STILL OPEN: ChatPreloadTopRequested is a no-op (the last residual — history pagination above the fold) |
| N-1 | android APK | GUI-default on android is runtime-unverifiable in-sandbox (no emulator/device); expected: the empty Material surface, not a black zombie | session 405 (js sibling); js live-verified in 406; APK artifact on build 42622715804 | owner installs the uniclient-android APK artifact and reports |
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build 42597570851 | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
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

## Session 416 — search-results sections: the global-search wire + presentation (2026-11-11)

- Boot: sync clean (main == origin, all session-415 pushes landed), Build (d6377325)
  42873030894 + Pages 42873536058 green; Verify 42873080126 still in flight at boot
  (cross-builds + nix legs green, test leg running) — result recorded at yield.
  Reference research fetched this session (AyuGramDesktop dev + lib_ui master-ui):
  dialogs_inner_widget.cpp paint flow + offsets, dialogs.style searchedBar tokens,
  colors.palette, dialogs_widget.cpp kSearchRequestDelay, lang.strings labels.

- Atomic 1 (the global-search wire — engine + port + app law): engine
  SearchGlobalChats carries Username and NO LONGER falls back to local rows on a
  core error (a failing server search is an honest error; the old fallback would
  have shown local rows duplicated under the section) — the redundant
  globalSearcher type-assertion deleted (SearchGlobal is on the Core interface);
  telegram SearchGlobal carries Username (users + channels). BONUS BUG found by
  probe + fixed (pre-existing): SearchChats's SELECT was 3 columns short of
  scanChats's 51 destinations (mute_until, theme_emoticon, wallpaper_json) — the
  local chat search ALWAYS errored `expected 48 destination arguments in Scan,
  not 51`, masked until now by the removed fallback consuming its error.
  ChatPort gains SearchGlobalChats(accountID, query) — ChatInfo → dialogs.Entry
  rows; the preview law is the reference's search-row text law
  (paintPeerSearchResult 2010-2040): `@username`, username-less rows show
  `ID: <id>`. App: GlobalSearchState (TypedAt/Fired/Resolved/Query/Rows) +
  SearchGlobalLoaded msg + the 900ms debounce (the reference's kSearchRequestDelay,
  dialogs_widget.cpp:122) riding DialogsTick (SearchGlobalPending keeps the window
  frame loop flowing while armed) + one Cmd looping the model's accounts in order
  (50-page, the reference kSearchPerPage) + stale-drop on query mismatch + the
  exact-'@' mentions mode never fires (the reference would fire contacts.search
  for the literal '@' — degenerate; our call: the mentions mode is a local view)
  + full reset when the text empties. Red->green: engine
  TestSearchGlobalChatsCarriesUsername (red: Username "") +
  TestSearchChatsScansFullRow (red: the scan mismatch) +
  TestSearchGlobalChatsCoreErrorIsHonest (red proven by re-adding the fallback
  against the fixed SearchChats: 'must surface its error, not local rows') +
  TestSearchGlobalPortMapsRows (red: method missing); gui journey pins
  TestSearchGlobalDebounceFiresOnceAndResolves (fire at exactly 900ms, per-account
  order, resolve, no re-fire) + MentionsModeNeverFires + StaleResultsDropped +
  ClearsWithText + RetypingRefires (re-arm honors the full delay again).
  ChatKind* exported (the wire contract shared app/appport).
- Gates (atomic 1): quick gate GREEN scoped (tests/engine 7.0s, tests/gui,
  tests/ui, bootstrap, cores 59s; app/appport/window/cmd + renders via windows
  vet), gofmt clean, comment ban clean (379 files), js/wasm full-tree build green.

- Atomic 2 (the sections presentation — the reference's results layout,
  dialogs_inner_widget.cpp paint flow): Filtered state = local rows (bare, no
  header — the reference paints _filterResults headerless) then ONE section
  slot: the 28dp searched bar (st::searchedBarHeight/Font/Position from
  dialogs.style 805-807 -> tokens SearchedBarHeight=28/SearchedBarPadX=14/
  SearchedBarTextTop=5/FontSearchedBar=FontBase; bar bg SurfaceContainer over
  the dialogs SurfaceContainerLow — the Material read of searchedBarBg
  windowBgOver-over-dialogsBg; bar fg OnSurfaceVariant — windowSubTextFgOver)
  showing 'Loading...' while unresolved-with-no-rows (lng_contacts_loading) or
  'Global search results' when rows exist (lng_search_global_results — stale
  rows persist under the results bar until replaced, exactly the reference's
  keep-until-received law) + global rows (same dialog-row painting, stitched
  after the bar). dialogs.List gains Global/GlobalBar/BarText with the geometry
  law in one place: Height = local + 28 + global rows; RowAt walks the stitched
  space, the bar itself returns -1 (not selectable); EntryAt/RowCount expose the
  stitch; Pane carries Global/GlobalRowYs/GlobalBarY/BarText/GlobalFirst with
  the same absolute-Y projection + viewport clipping as local rows; the
  scrollbar/MaxOffset cover the sectioned height automatically. App stitches
  m.GlobalSearch into the List in setDialogRows (loading = armed && !resolved,
  armed now requires accounts — a zero-account search never arms, fixing the
  eternal-loading-bar seam atomic 1 would have shown on the empty live page);
  the stitched selection law: DialogRowPressed/openCmdAfterPress/selectDialogRow
  use RowCount/EntryAt; selection retention extends to global rows (a selected
  global chat survives reprojections); applySearchGlobalLoaded reprojects.
  red->green: tests/ui dialogs_search_sections_test.go (Heights incl. bar-only,
  RowAt incl. the bar's -1, EntryAt/RowCount, Pane geometry + partial
  visibility + no-bar, scrollbar coverage) — red: fields/tokens missing;
  tests/gui app_search_global_test.go additions (pane stitches Loading... ->
  results bar + rows + clear drops the section; press on a global row selects +
  fires the open cmd driving port.Messages with the global row's account/chat —
  the full journey; zero accounts never arms; PaintPane records the sectioned
  pane without panic at all three states).
  §4 evidence: the gui journey drives the app model through the real
  press->open seam; the live wasm page cannot drive the section (zero accounts,
  no add-account surface yet) — BLOCKED-env, the section seam is pinned at the
  pane/paint-op level; the in-sandbox pixel decode needs a GPU/window the VM
  lacks (gio cgo legs ride CI) — the bar's geometry is token-pinned instead.
- Gates (atomic 2): quick gate GREEN scoped (tests/engine 7.1s, tests/gui,
  tests/ui native; app/appport/dialogs/render/window/cmd + renders via windows
  vet), gofmt clean, comment ban clean (380 files), js/wasm full-tree build
  green.

- Atomic 3 (PaintComposeBar GAINS its caller — the W-2 zero-caller seam
  closed): the rebuilt GUI's compose field was invisible while typing worked
  (routeComposeKeys + the compose model were live; the paint had zero callers
  — degraded-UX severity, the input surface painted nowhere). Fix:
  PaintChatPane restructured — the messages clip (Width x View.Height) now
  pops BEFORE the compose bar paints: the body (empty text, rows, date badges,
  down/mentions/reactions buttons, scrollbar) extracted verbatim into
  paintChatBody so the early returns can't strand the op stack, then
  PaintComposeBar rides the pane's own coordinate space (its geometry is
  window-height-based: the field band sits exactly in the viewport's reserved
  ComposeBarHeight below the messages clip). red->green:
  tests/ui history_render_paint_pin_test.go — a source-scan pin (the
  family_tags pattern): PaintChatPane's body must call p.PaintComposeBar —
  red: 'the W-2 zero-caller seam: the field would be invisible while typing
  works'; + the gui journey TestOpenedChatCarriesComposePane (press ->
  ChatLoaded -> CanSend -> ComposePane.Shown) pinning the chain that feeds
  the bar; TestFeedPaintSmoke re-exercised with a live Compose pane
  (record-without-panic). §4: live pixel drive BLOCKED-env (needs an open
  chat -> an account; no add-account surface yet).
- Gates (atomic 3): quick gate GREEN scoped (tests/gui, tests/ui;
  render/window/cmd via windows vet), gofmt clean, comment ban clean (382
  files), js/wasm full-tree build green.

- Atomic 4 (the search-EMPTY state — the reference's MakeSearchEmpty widget,
  chat_search_empty.cpp + dialogs.style 717-720 + lang.strings 8540-8541
  fetched this session): Filtered state with NOTHING to show (local rows
  empty, no section bar — resolved-empty or the '@' mode with no mention
  rows) now paints the honest empty state instead of a blank pane: the
  220dp band (recentPeersEmptyHeightMin) with 'No Results' (bold,
  lng_search_tab_no_results) + 'There were no results for "{query}".'
  (lng_search_tab_no_results_text; the query preview capped at 32 runes —
  the reference's kQueryPreviewLimit mid(0,32) law) centered at
  SearchEmptyTextTop = (220-100)/3 + 100 + 10 (the reference's icon-slot
  formula: icon 100dp at h/3, label below + skip 10 — the lottie icon is
  banned-cluster, its slot's geometry is the law; a static glyph returns with
  the icon front), labels width-capped at pane - 2*10 (recentPeersEmptyMargin).
  dialogs.List gains SearchEmptyShown/Title/Line (Height adds the 220 band —
  the reference h = searchedOffset + 220) + SearchEmptyQueryPreview (32-rune
  cap, exported pure law); the Pane carries the composed strings (the app
  owns user-facing strings — it composes the line); the painter paints the
  two centered labels (title OnSurface semibold, line OnSurfaceVariant) and
  the guard order keeps AddAccountPrompt (zero accounts) exclusive with the
  search empty (armed requires accounts — the app law from atomic 2).
  red->green: tests/ui dialogs_search_empty_test.go (preview cap table incl.
  the 32/33 boundary, the 220 height, pane passthrough, the icon-slot
  formula token pin) — red: fields/tokens missing; tests/gui additions
  (resolved-empty shows 'No Results' + the line + no section bar;
  40-char query -> the 32-char preview law; the '@' mode shows it
  immediately — no loading wait; unresolved stays hidden; paint records
  without panic). §4: live drive BLOCKED-env (needs accounts).
- Gates (atomic 4): quick gate GREEN scoped (tests/engine 6.9s, tests/gui,
  tests/ui native; app/appport/renders/window/cmd via windows vet), gofmt
  clean, comment ban clean, js/wasm full-tree build green.
