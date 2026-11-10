# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: GUI rebuild (§6); W-2 feeds atomic landed (session 410): the pump now
  decodes chat_snapshot -> dialogs rows (per-account replace, merge in account
  order, selection follows identity) and msg_received for the open chat -> live
  append with re-derived grouping/dividers; row press opens the chat through
  the new ChatPort seam (appport.For(engine) wired in window.Run, portless
  press = selection only); item projection pinned to the mined reference laws
  next front work: the search filter semantics (rows exist -> filter), then
  chat_updated live row updates, then D-4 atomic 2
- next: filter semantics, chat_updated rows, D-4 atomic 2, D-3
- owner-waiting: N-1 — install the uniclient-android APK artifact
  (build 42622715804) on a device and report (android GUI-default check)
- last-gate: session 410 — quick gate GREEN (native vet+test scoped —
  tests/engine 6.7s, tests/gui, tests/ui, dialogs, history; windows vet gio
  legs), gofmt + comment ban clean (367 files); js/wasm 32,032,288 B (CI
  recipe) driven under the real CI shell on localhost: 1440x900 prompt 84 px
  @ 935..1019 x 445..454 center (977,450) = chat-pane center, W-1 placeholder
  + pill intact (64.13% Surface + 34.62% container + 1.19% pill); 390x844
  prompt center (195,448) = list-area center (195,449); console + page errors
  empty both shapes. CI on 4b3f0906: Build #11 (42780364759) all five jobs
  + Verify #409 (42780429420) all jobs+steps GREEN (comment ban, gofmt,
  vet, live vet, test, race, headless smoke, windows + js/wasm cross,
  nix) + Pages deploy #27 (e354e265) fresh.

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| W-1 | ui/app InitialModel | CLOSED 2026-11-09 (session 408): the zero-account scene now paints the frame — dialogs column SurfaceContainerLow vs chat Surface, 54dp header band, the reference-measured search field (7,9,W-18,35 r18) with real focus/typing/backspace/blink; driven live at 1440x900 + 390x844 (pixel scan: pill exact, ring+caret+typed text verified). The residual — the engine-driven add-account affordance — moved to the new front item below | session 408 driven journey | done |
| W-2 | app/engine bridge | PART: feeds atomic landed (session 410 — chat_snapshot -> rows via the pump with identity, open journey via ChatPort -> ChatLoaded -> bottom jump, msg_received live append; the wire proven against the real engine: SyncChats -> real JSON -> app rows, HandleUpdate -> real msg_received JSON -> app append); STILL OPEN: the search field filters nothing yet, PaintComposeBar still has zero callers, chat_updated row updates unconsumed, msg-level unread bars need read-position, ChatPreloadTopRequested is a no-op (MoreAbove always false) | session 410 driven journey + wire tests | the filter semantics atomic (rows exist -> filter pinned by tests); then chat_updated -> live row content updates |
| N-1 | android APK | GUI-default on android is runtime-unverifiable in-sandbox (no emulator/device); expected: the empty Material surface, not a black zombie | session 405 (js sibling); js live-verified in 406; APK artifact on build 42622715804 | owner installs the uniclient-android APK artifact and reports |
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build 42597570851 | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |
| D-3 | build.yml web job | wasm size diet: the js/wasm build ships every core incl. the six raw-TCP backends that can never connect from a browser (§7 web truth) — build-tag exclusion at the engine factory projected <20 MB; also headroom under git's 100 MB file ceiling on gh-pages | headless-host wasm = 31,162,944 B after the keyboard atomic (v0.9.1's old-GUI build was 88,659,256 B) | one atomic with tests: bootstrap factory js variant + per-core js stubs |
| D-4 | window keys — atomic 2 | Enter=submit (ShouldSubmit law: default Enter-mode = plain Enter/Return submits, Shift/Ctrl+Return newline — already mapped) -> ChatComposeSubmitted + send-request seam (ChatBottomRequested-pattern) + field clear; Up/Down/PageUp/PageDown = history scroll (never compose cursor moves — customUpDown law); Up on EMPTY field + canWrite + !edit + !reply -> edit last editable message, else scroll; Ctrl+Up/Down -> reply prev/next (reply front) | AyuGramDesktop dev history_widget.cpp 9276-9349 (fetched 2026-11-09): Down always _scroll->keyPressEvent; Up scrolls unless field empty && canWrite && !_editMsgId && !_replyTo, then lastEditableMessage() -> editMessage else scroll; PageUp/PageDown always scroll; Enter -> ShouldSubmit(sendSubmitWay, mods); Qt key scroll = SliderSingleStep/PageStep (qabstractscrollarea.cpp 1215-1220; qabstractslider.cpp 180: defaults singleStep 1 pageStep 10 — but our own wheel law 120-angle notch = 60px = WheelScrollLines 3 => singleStep = 20px = WheelNotchAngleDelta/WheelScrollLines/WheelPixelToAngleDelta); IME ranged EditEvents + SelectionCmd/SnippetCmd contract = the mobile/IME front | atomic 2: ChatComposeSubmitted + ChatComposeSendRequested + scroll keys with the 20px singleStep law; edit-last rides the messages/edit front |

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

## Session 409 — W-2 the engine->UI bridge: the gui path is live (2026-11-10)

- Boot: sandbox recycled to zero (toolchain rebuilt per env.sh, module
  cache refilled); CI gap closed: Build #9 (42665034482, a257c378) all
  jobs SUCCESS + Pages deploy #25 green — session 408's push.
- W-2 bridge atomic (the gui path had ZERO engine wiring): main.go boots
  bootstrap.Init on BOTH paths now (gui returns before the signal wait);
  window.Run(eng) subscribes and pumps engine JSON -> app.EngineEventMsg
  (raw chan 256 deep, non-blocking send on the emitter callback, single
  pump goroutine -> msgs + Invalidate, done channel closes at destroy);
  Subscribe/SetEventCallback replay the account snapshot to the new
  callback FIRST (snapshot marshaled before e.mu, cb called under e.mu:
  emitters serialize through PushEvent so the replay-before-register
  order is airtight; the pump callback must stay non-blocking —
  contract); app decodes the account_list wire into Model.Accounts
  (sort_order, id tiebreak) and projects the honest zero-account state:
  len(Accounts)==0 -> "Add an account" centered in the chat pane
  (two-pane) or the dialogs list area (single-pane), FontBase
  OnSurfaceVariant; the add-account BUTTON stays hidden until the login
  front exists (§1.9 dead-button ban). emitAccountList refolded onto
  accountListEvent (one marshal path).
- Tests: tests/gui/app_engine_bridge_test.go NEW (11: wire decode +
  order, empty/unknown/malformed/bad-data ignored, prompt projection at
  both pane shapes, accounts-present no prompt, InitialModel nil, paint
  smoke both renderers both shapes); tests/engine events re-pinned for
  the replay (deliberate behavior change — subscriber counts now include
  it) + 2 new replay-contract tests (first-and-fresh, nil-clears).
- Driven (§4, the shell assembled from build.yml verbatim, wasm
  31,199,016 B, agent-browser): console + page errors EMPTY; 1440x900 —
  split intact (64.27% Surface + 34.41% container + 1.26% pill),
  placeholder 52 px @ 20..58 x 21..30, prompt 89 px @ 933..1019 x
  445..454 center (971,450) = chat-pane center; click (100,27) -> ring
  2004 px @ 5..504 x 7..45 (the 2dp law, W-1 intact); 390x844 — prompt
  96 px @ 150..237 x 444..453 center (189,449) = list-area center;
  localStorage uniclient.vault created by the engine boot.
- Gates: quick gate GREEN (native vet+test scoped — tests/engine 6.1s,
  tests/gui, tests/ui, tests/bootstrap all ok; windows vet for the gio
  cgo legs), gofmt clean, comment ban clean (363 files). README web
  paragraph updated (the bridge landed). BLOCKED-env: the native
  headless/gui drive needs the X11 cgo libs — CI verify covers it.
- Next: feeds atomic (chat_snapshot -> rows via the pump), then filter
  semantics; D-4 atomic 2; D-3.

## Session 408 — full recon (owner order) + W-1 closed: the zero-account frame (2026-11-09)

- Owner redirect: "still broken, do full recon before continuing." Recon
  first, then the fix. Recon findings (all command-verified this session):
  local main == origin/main == a85ec25a, clean tree; PRs #1/#3 = old
  closed owner test/doc PRs (irrelevant); CI Build #8 (42647039235,
  dispatched on a85ec25a, unrecorded in STATE until now) all five jobs
  SUCCESS + Pages deploy e0e69862 green — the live URL serves VER
  a85ec25a, wasm 31,162,944 B; live drive (agent-browser, 1440x900 +
  390x844): boots clean (HUD none, canvas 1, console + page errors
  empty) but the viewport is STILL 100.00% one color #FEF7FF — the
  owner's "still broken" = W-1, confirmed with this session's own eyes.
  Code-level root cause mapped: window.go paints Background + two panes;
  dialogs PaintPane draws rows only; chat PaintChatPane early-returns
  at Count<=0; PaintComposeBar has ZERO callers (dead code — W-2);
  the gui path runs window.Run() with no engine wiring at all.
- W-1 atomic (the visible frame): tokens measured from the reference —
  dialogs.style dialogsFilter (heightMin 35, radius 18, textMargins
  12/8/30/5, borderActive 2), dialogsFilterPadding 7/7, dialogsFilterSkip
  4, the top bar 54 (info.style topBarHeight — already in the table),
  composition from dialogs_widget.cpp updateControlsGeometry 4642-4710:
  filterLeft = padX + menuW + padX (54 with the hamburger, 7 without —
  the hamburger is DEFERRED to the menu front: no working menu items
  exist, a dead button is banned §1.9), filterRight = skip + padX = 11,
  field top = (54-35)/2 = 9; placeholder = lng_dlg_filter "Search"
  (no leading icon in the reference field). New: ui/dialogs/header.go
  (HeaderView + HeaderLayout + HeaderFieldHit), Pane.Header, app/search.go
  (SearchState + DialogsHeaderPressed/SearchTyped/SearchBackspace/
  SearchFocusLost + focus/blur/blink — the same CursorFlashTimeMs/2
  law), search_keys.go (SearchEditMsg single-line, ranged IME edits nil
  until the IME front — the compose pin; SearchKeyMsg: Backspace only,
  arrows/copy deferred to the field-kit front), window.go routing
  (band press -> DialogsHeaderPressed in pane coords, list events
  shifted -54; routeSearchKeys mirrors routeComposeKeys incl.
  SoftKeyboardCmd; pressDialogs blurs the search — a list press is
  outside the field), painter: the dialogs column fills
  SurfaceContainerLow (M3 list-pane law; the chat column keeps Surface
  — the two-pane split), the band + pill (SurfaceContainerHighest,
  focused ring Primary 2dp) + placeholder OnSurfaceVariant + caret;
  Resized: DialogsScroll.Height = H-54 (the list is a separate
  scrollable below the fixed band, the reference's own structure).
- Tests: dialogs_header_elm_test.go NEW (11 tests: geometry at both
  pane shapes, scroll height, focus journey incl. list-press blur and
  band-press-leaves-list-untouched, typed/backspace, blink law, focus
  lost, zero-account scene pins the header, view projection, paint
  smoke). Deliberate behavior change — the 54dp band — re-pinned in the
  six dialogs test files (scroll clamp 72->126, viewport 300->246,
  load-more line 92->254, wheel accel 270->243 (areaH 246), track jump
  346->486, bar drag scale 33->41, rubber band 702/10/196->750/4/88,
  spring return 700/695/693/692->749/747/746/746, fling settle 692->746,
  to-up press Y 360->306, hidden-bar 4 rows->3) — every pin recomputed
  from the law, not copied: rubber band 44 leftover x2 /20 = 4.4 -> 4,
  spring 4xe^(-12.5t), wheel -60x246/120 = 123. tests/gui 197 (186+11).
- THE CARET BUG (found by the drive, fixed): fillRRect with radius 1 on
  a 2dp-wide rect paints NOTHING on gio/js (degenerate rounded-rect
  path); the ring (radius 20) and pill (18) painted fine, the caret was
  invisible at both blink phases — isolated by two debug builds
  (unconditional gate still invisible; radius 0 + W 8 painted 128px at
  the exact computed geometry 19,18). Fix: caret radius 0 (a 2dp
  hairline has no rounding). Painter law: hairline fills use radius 0.
- Driven journey (§4, the fixed build under the real CI shell on
  localhost, agent-browser): 1440x900 — pixel histogram 64.31%
  #FEF7FF + 34.37% #F7F2FA + 1.29% #E6E0E9 (the split) + #49454F
  (placeholder); pill bounds scanned 7..502 x 9..43 = the measured
  table exactly; click (100,27) -> focus ring 2dp #6750A4 + caret
  2x16 at (19,18); press a,b -> text painted, caret moved to x 34-35
  (follows the text); blink over 5 shots: ON off ON ON off (500ms
  law); 390x844 single-pane: pill + ring visible (95.73% container +
  3.72% pill). Console + page errors clean at both sizes.
- Gates: quick gate GREEN (native vet+test scoped, windows vet for the
  gio legs), gofmt clean, comment ban clean, js/wasm full build green
  31,183,083 B. Boot: sandbox had recycled to zero (Go 1.27.3
  reinstalled per env.sh, module cache refilled).
- Docs: README web paragraph now says what the page shows (frame +
  empty lists until the bridge lands); STATE records Build #8; W-1
  CLOSED, W-2 opened (the engine->UI bridge — the add-account
  affordance needs it; the search filter semantics ride it too).
