# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: GUI rebuild (§6); D-3 (wasm size diet) IN PROGRESS — atomic 1
  landed: the engine no longer speaks concrete cores or gotd —
  telegramLoginFlow/baleSubmitter/peerBarController/phoneSharer/botPhotoSetter/
  notifyDelayGetter/langPackGetter/geoTileFetcher capability interfaces replace
  every *cores.TelegramCore|BaleCore assertion (19 sites, auth.go 12 + 2 bale +
  cache_users 7); the 21 engine-cache schema types moved to the untagged
  cores/telegram_data.go (pure structs, zero imports, gotd-free — measured);
  the two gotd-shaped seams genericized (UploadGetWebFile -> GetGeoWebTile
  (GeoWebFileQuery) []byte; LangpackGetLanguages -> []LangPackInfo); engine
  imports no gotd. New pins red->green: tests/engine/engine_decoupling_test.go
  (gotd-import ban + concrete-core roster ban). next: D-3 atomic 2 — the
  exclusion itself (build tags + bootstrap factory js variant + webbuild js test)
- next: D-3 atomic 2
- owner-waiting: N-1 — install the uniclient-android APK artifact
  (build 42622715804) on a device and report (android GUI-default check)
- last-gate: session 414 atomic 1 — quick gate GREEN (scoped: bootstrap,
  cores, engine, tests/bootstrap 1.0s, tests/cores 59.2s, tests/engine 6.9s;
  windows vet gio legs), gofmt + comment ban clean (373 files), js/wasm
  build green; CI record for session 413's pushes: Build #16 (ff00c1e2)
  + Verify #412 (42838556241, all 3 jobs + steps) green, Build #15 green,
  Build #14 cancelled by the build.yml cancel-in-progress policy (superseded
  push — not a red gate), Pages serving; CI dispatch on this push follows
  (record next session).

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| W-1 | ui/app InitialModel | CLOSED 2026-11-09 (session 408): the zero-account scene now paints the frame — dialogs column SurfaceContainerLow vs chat Surface, 54dp header band, the reference-measured search field (7,9,W-18,35 r18) with real focus/typing/backspace/blink; driven live at 1440x900 + 390x844 (pixel scan: pill exact, ring+caret+typed text verified). The residual — the engine-driven add-account affordance — moved to the new front item below | session 408 driven journey | done |
| W-2 | app/engine bridge | PART: msg_received row bump landed (session 413 — engine emits the full bumped row: handleNewMessage increments unread before the row-update emit, ONE chat_updated per incoming message with preview/date/unread/move; REAL-seam wire test pins HandleUpdate -> chat_updated bytes -> app rows for a non-open chat); payload unification landed (session 413 — JoinChannel/ClearHistory emit emitChatUpdate's full row; ONE chat_updated wire shape); chat_updated atomic landed (session 412 — full-payload chat_updated drives live row content: ONE snapshotRow mapping path, replace-or-insert into accountRows, engine list law sorted locally (pinned DESC, last_msg_time DESC), filter+identity-selection reapplied, snapshot-equivalence pinned); filter atomic landed (session 411 — typed search filters the rows: SearchWords/MatchesWords law in ui/dialogs/search.go, word-prefix + accent/case fold + AND, selection = row identity across filter cycles); feeds atomic landed (session 410); STILL OPEN: PaintComposeBar zero callers, msg-level unread bars need read-position, ChatPreloadTopRequested is a no-op, transliteration/username/"@"-mentions matching + the search-results sections ride the search front | session 413 wire tests | D-4 atomic 2 |
| N-1 | android APK | GUI-default on android is runtime-unverifiable in-sandbox (no emulator/device); expected: the empty Material surface, not a black zombie | session 405 (js sibling); js live-verified in 406; APK artifact on build 42622715804 | owner installs the uniclient-android APK artifact and reports |
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build 42597570851 | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |
| D-3 | build.yml web job | wasm size diet: the js/wasm build ships every core incl. the six raw-TCP backends that can never connect from a browser (§7 web truth) — build-tag exclusion at the engine factory projected <20 MB; also headroom under git's 100 MB file ceiling on gh-pages | headless-host wasm = 31,162,944 B after the keyboard atomic (v0.9.1's old-GUI build was 88,659,256 B) | one atomic with tests: bootstrap factory js variant + per-core js stubs |
| D-4 | window keys | ATOMIC 2 LANDED (session 413): plain Enter/Return -> ChatComposeSubmitted -> composeSubmittedCmd (guards: open+port+CanSend+non-empty) clears the field and fires ChatPort.Send -> ChatComposeSendRequested{OK,Text}; failed sends restore the field (composeEdit — no data loss); Up/Down arrows = ChatScrolled step 20dp, PageUp/PageDown = 200dp (tokens ScrollKeyStep = WheelNotch/WheelScrollLines/WheelPixelToAngleDelta, ScrollKeyPageStep = 10x — the Qt qabstractslider defaults through the wheel law); CanSend lands on the open transition from the row type (channels read-only — honest default until the writability front carries admin rights); REAL-seam: appport.Send -> engine.SendMessage -> optimistic msg_received -> open-chat append (wire test). Residuals: Up-on-empty-field edit-last rides the messages/edit front (scrolls meanwhile), Ctrl+Up/Down reply-cycle rides the reply front, scroll keys need compose focus — the unfocused chat pane has no key routing yet (window front) | history_widget.cpp 9276-9349 (fetched 2026-11-09) + qabstractslider defaults | IME ranged EditEvents + SelectionCmd/SnippetCmd contract = the mobile/IME front; window-front key routing |

## Session 414 — D-3 atomic 1: the engine speaks interfaces, not cores (2026-11-10)

- Boot: sandbox recycled — toolchain + module cache survived under ../toolchain
  (env.sh re-sourced, go 1.27.1; build cache warm only under the CGO_ENABLED=1
  recipe — a CGO_ENABLED=0 run re-keys the whole cache and OOMs on gotd's tg;
  use the dev-test/gate recipe), .env intact (gitignored, askpass push intact).
  CI for session 413's pushes recorded: Build #15 (c5cd8751) + Build #16
  (ff00c1e2) green, Verify #412 (42838556241) all 3 jobs + steps green on
  ff00c1e2, Build #14 (2dc365c8) cancelled by build.yml's own
  cancel-in-progress concurrency policy (superseded mid-run — not a red
  gate), Pages builds serving.
- The law (D-3 precondition, rated: the concrete-assertion engine was <7/10
  against the §6.3/§7 capability law — replaced, not patched): the engine
  projects per-core features through interfaces and never references a
  concrete core or a core SDK type — otherwise no build-tag core exclusion
  can ever shrink the js link graph. Research (identifier-definition map,
  engine vs the six raw-TCP families): 19 concrete assertions
  (auth.go 12 telegram + 2 bale; cache_users.go 7), 21 engine-cache schema
  types defined inside the telegram family (all pure structs, gotd-free —
  regex-audited), exactly one gotd import in the whole engine
  (cache_users.go, the GetMapTile tg web-file request + LangPackGetLanguages
  tg return).
- Change: telegramLoginFlow (16 methods, the login machine) + baleSubmitter
  in engine/auth.go; peerBarController/phoneSharer/botPhotoSetter/
  notifyDelayGetter/langPackGetter/geoTileFetcher in engine/cache_users.go —
  house-pattern interfaces at their call sites; every assertion target
  swapped, zero behavior deltas (wrong-core paths return the same errors);
  the 26-method surface maps 1:1 onto the real signatures (extracted, not
  transcribed). cores/telegram_data.go NEW (untagged): JoinAsPeerInfo,
  AdminLogEvent, ChatPermissionFlags, DefaultBannedRights, ParticipantExtra,
  BotCommandEntry, InlineBotResults, ForumTopicIconInfo, ChannelUsernameInfo,
  PasskeyInfo, CloudPasswordState, PasswordResetResult, ChatNotifySettings,
  PeerColorEntry, CloudThemeInfo, ChatThemeInfo, WallpaperInfo,
  CallHistoryEntry (telegram.go) + DiceSticker, DiceStickersResult
  (telegram_dice.go) + ChannelStats (telegram_stats.go) + the two new seams
  GeoWebFileQuery and LangPackInfo. Telegram methods reshaped:
  UploadGetWebFile(*tg.UploadGetWebFileRequest) (*tg.UploadWebFile) ->
  GetGeoWebTile(GeoWebFileQuery) ([]byte, error) (the engine's clamp law
  stays engine-side; the tg request build moves core-side);
  LangpackGetLanguages -> []LangPackInfo (field-mapped). Engine's gotd
  import deleted.
- Tests: tests/engine/engine_decoupling_test.go NEW, seen RED first —
  TestEngineImportsNoCoreSDK (cache_users.go "github.com/gotd/td/tg") and
  TestEngineAssertsNoConcreteCore (auth.go:136 *cores.TelegramCore; the
  pinned roster covers all 10 concrete cores — a new core joins by
  extending the pin) — then GREEN. All existing suites green zero re-pins:
  tests/engine 6.9s, tests/bootstrap 1.0s, tests/cores 59.3s (telegram
  scripted-server legs through the reshaped seams included). Edits via
  byte-exact python patch (sessions 410-412 landmine) with count-verified
  anchors; gofmt fixed three authored-file nits (alignment, import blank,
  test-file tabs) — gofmt -l . clean.
- Gates: quick gate GREEN (scoped: bootstrap, cores, engine,
  tests/bootstrap, tests/cores, tests/engine; windows vet gio legs),
  comment ban clean (373 files), js/wasm build green (engine + cores +
  bootstrap + cmd).
- Next: D-3 atomic 2 — !js build tags on the six raw-TCP families,
  bootstrap factory js variant (github/matrix/bale trio, honest error for
  the rest), tests/webbuild js pin under the wasm runner, family-tag
  source-scan pin, measured size drop.

## Session 413 — W-2 wire atomics + D-4 atomic 2: row bumps, ONE payload shape, window keys (2026-11-10)

- Boot: sandbox recycled to zero — toolchain rebuilt per env.sh (go 1.27.1,
  module cache refilled 1.1G), .env re-created from the owner token
  (gitignored, askpass push intact); CI for session 412's push recorded
  green: Build 42803562918 all five jobs + Verify 42803582751 all jobs+steps
  on ed008c69, Pages 42804202730 serving. (Doc fix in-run: the atomic-2
  commit accidentally shipped this entry duplicated — rebuilt single here.)
- Atomic 1 (msg_received row bump): handleNewMessage ran
  updateChatLastMessage (which emits chat_updated — the event the UI row
  path rides) BEFORE incrementUnread, so a bumped row's unread badge
  lagged by exactly one message; preview/date/move already worked
  (session 412 path). UI-side synthesis rated <7 (duplicates engine law:
  unread counters, group preview needs chat type the msg_received payload
  lacks) — replaced, not patched: engine reorder, ONE event carrying the
  full authoritative DB row. Test red->green:
  TestNewMessageWireBumpsNonOpenChatRow (snapshot seeds c1 unread 2 below
  newer c2; REAL HandleUpdate new message in non-open c1 -> captured
  chat_updated bytes -> app rows: unread 2->3, preview "alice: live wire",
  date vs the captured envelope ts, c1 moves to top, non-open chat grows
  no items). Red seen first: "the bumped row must carry the incremented
  unread, got 2, want 3".
- Atomic 2 (chat_updated payload unification): JoinChannel + ClearHistory
  were the last bare-map chat_updated emitters ({"account_id","chat_id"}) —
  shapes the UI decodes to an empty ChatID and drops. Both now call
  emitChatUpdate: the full row re-read from the DB, ONE wire shape for
  chat_updated; no-row still emits nothing (Scan-err early return). Test
  red->green: TestJoinChannelAndClearHistoryEmitFullRowChatUpdated (stub
  core with JoinChannel/DeleteChatHistory -> SyncChats seeds the row ->
  REAL JoinChannel/ClearHistory -> captured chat_updated decodes
  chat_id/title/unread/last_msg_text through the {chat} shape -> app rows
  survive both events). Red seen first: 'JoinChannel must emit the
  unified full-row payload, got: {"account_id":"a1","chat_id":"c1"}'.
  No other consumer pinned the legacy shape (grep-verified).
- Atomic 3 (D-4 atomic 2, window keys): ComposeKeyMsg maps plain
  Enter/Return -> ChatComposeSubmitted (Ctrl/Shift+Return keep the newline
  law), Up/Down/PageUp/PageDown -> ChatScrolled deltas through tokens
  ScrollKeyStep (=WheelNotchAngleDelta/WheelScrollLines/WheelPixelToAngleDelta
  = 20) and ScrollKeyPageStep (=10x = 200) — the customUpDown law: vertical
  arrows NEVER move the compose caret. Update: ChatComposeSubmitted ->
  composeSubmittedCmd guards (open + port + CanSend + non-empty) -> clears
  the field (composeEdit("",0)) -> Cmd fires ChatPort.Send ->
  ChatComposeSendRequested{OK,Text}; failure restores the field text (no
  data loss). ChatPort gains Send; appport delegates to engine.SendMessage;
  the optimistic message lands in the open chat through the REAL
  msg_received wire (wire test pins items +1, Out, Sending). CanSend
  wiring: openCmdAfterPress captures row.ChatType != ChatChannel ->
  openCanSend; ChatLoaded lands it on the open transition (broadcast
  channels read-only — the honest default until the writability front
  carries admin rights). Regression caught by the gate and fixed in-run:
  ChatLoaded initially set CanSend on EVERY replay, stomping unit-journey
  preconditions (compose_elm viewport/resize pins) — moved inside the
  openLoaded transition (CanSend changes on open, not on content reload).
- Tests red->green (atomic 3): compose_keys_test.go table +7 (submit,
  arrows, page steps) with the ignore list re-pinned (7 now-mapped keys
  leave it — the law changed, pins updated in-commit);
  compose_submit_test.go NEW (5: send+clear journey with a recording fake
  port, failure restores, guards (no open / read-only / portless /
  empty), CanSend-from-row-type open journey, scroll-key clamp table);
  app_chat_wire_test.go +1 REAL-seam (port.Send -> optimistic
  msg_received -> open-chat append). BLOCKED-env: the driven wasm page
  cannot reach the compose (zero accounts -> no open chat) — the seam is
  proven at the wire boundary instead, session-410 precedent.
- Gates: quick gate GREEN three times (scoped: engine, tests/engine 6.4s,
  tests/bootstrap, bootstrap; then tests/gui, tests/ui, ui/* — gio cgo
  legs via windows vet), gofmt clean, comment ban clean (371 files),
  js/wasm build green. tests/gui out of scope for the engine atomics by
  construction — the wire seam (raw JSON bytes) keeps ui/app engine-free.
- Next: D-3.

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
