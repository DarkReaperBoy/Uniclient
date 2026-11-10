# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: GUI rebuild (§6); the search front's MATCHING LAYER CLOSED (session
  415, four atomics): (1) chat_updated carries the row's username (the
  unified full-row law completed); (2) NameWords(name, username) +
  MatchesNameWords replace MatchesWords — Entry.Username + the wire decode
  landed with it; (3) the reference fillNames law complete — translitRusEng
  + rusKeyboardLayoutSwitch (eng<->rus AND eng<->ukr, divergent slots
  space-joined) + removeAccents as the 695-entry lib_ui RemoveOneAccent
  table port (fixed the pre-existing foldAccents bug: NFD destroyed й and
  diverged from the reference on ё); (4) the exact-'@' mentions mode filters
  to mention rows. next front work: search-results sections
  (chats/contacts/global grouping — the reference's results presentation)
  and PaintComposeBar zero callers
- next: search-results sections (the visual grouping front)
- owner-waiting: N-1 — install the uniclient-android APK artifact
  (build 42622715804) on a device and report (android GUI-default check)
- last-gate: session 415 — quick gate GREEN on all four atomics (scoped:
  tests/engine <=6.5s, tests/gui, tests/ui native; gio legs windows vet;
  atomic 3 js/wasm full-tree build green), gofmt + comment ban clean
  (376 files); CI: Build (a3e8e0de) + Build (2e8ce1ca) green, Build
  (654d22f2) cancelled by build.yml's own concurrency policy (superseded
  mid-run — not red), Build (d6377325) + Verify 42873080126 dispatched on
  d6377325 in flight at yield — record the result next session

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| W-1 | ui/app InitialModel | CLOSED 2026-11-09 (session 408): the zero-account scene now paints the frame — dialogs column SurfaceContainerLow vs chat Surface, 54dp header band, the reference-measured search field (7,9,W-18,35 r18) with real focus/typing/backspace/blink; driven live at 1440x900 + 390x844 (pixel scan: pill exact, ring+caret+typed text verified). The residual — the engine-driven add-account affordance — moved to the new front item below | session 408 driven journey | done |
| W-2 | app/engine bridge | PART: the search matching layer CLOSED (session 415, four atomics — username on the wire + NameWords/MatchesNameWords with translit/keyboard-switch/removeAccents ported 1:1 from the reference + the '@' mentions mode); msg_received row bump + payload unification + chat_updated atomic + filter + feeds landed (sessions 410-413) | session 415 gates | STILL OPEN: PaintComposeBar zero callers, msg-level unread bars need read-position, ChatPreloadTopRequested is a no-op, search-results sections (the visual grouping front) |
| N-1 | android APK | GUI-default on android is runtime-unverifiable in-sandbox (no emulator/device); expected: the empty Material surface, not a black zombie | session 405 (js sibling); js live-verified in 406; APK artifact on build 42622715804 | owner installs the uniclient-android APK artifact and reports |
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build 42597570851 | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |
| D-3 | build.yml web job | CLOSED 2026-11-10 (session 414, two atomics — see the session entry for the evidence trail) | gotd = 0 packages in the js link graph; wasm plain build 32,837,371 -> 26,714,844 B (-6,122,527 B, -18.6%); <20MB projection did not hold — remaining bulk = web trio deps (mautrix+goolm, bale gRPC-web, pion webrtc) + the rebuilt GUI (gio+fonts) | done; CI web job ships the trimmed wasm from the atomic-2 push |
| D-4 | window keys | ATOMIC 2 LANDED (session 413): plain Enter/Return -> ChatComposeSubmitted -> composeSubmittedCmd (guards: open+port+CanSend+non-empty) clears the field and fires ChatPort.Send -> ChatComposeSendRequested{OK,Text}; failed sends restore the field (composeEdit — no data loss); Up/Down arrows = ChatScrolled step 20dp, PageUp/PageDown = 200dp (tokens ScrollKeyStep = WheelNotch/WheelScrollLines/WheelPixelToAngleDelta, ScrollKeyPageStep = 10x — the Qt qabstractslider defaults through the wheel law); CanSend lands on the open transition from the row type (channels read-only — honest default until the writability front carries admin rights); REAL-seam: appport.Send -> engine.SendMessage -> optimistic msg_received -> open-chat append (wire test). Residuals: Up-on-empty-field edit-last rides the messages/edit front (scrolls meanwhile), Ctrl+Up/Down reply-cycle rides the reply front, scroll keys need compose focus — the unfocused chat pane has no key routing yet (window front) | history_widget.cpp 9276-9349 (fetched 2026-11-09) + qabstractslider defaults | IME ranged EditEvents + SelectionCmd/SnippetCmd contract = the mobile/IME front; window-front key routing |

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

## Session 415 — the search front opens: username wire + reference matching (2026-11-11)

- Boot: sandbox recycled to zero — toolchain rebuilt per env.sh (go 1.27.1,
  module cache refilled), .env re-created from the owner token (gitignored,
  askpass push intact). Machine: cold build cache cost paid once (gotd's tg
  serial compile; vet leg re-key, documented §9 rung-7 shape — converges on
  re-run, cache carries progress).
- Atomic 1 (chat_updated carries the row's username): emitChatUpdate's SELECT
  omitted chats.username, so every row-replace event (read state, mute, pin,
  title, row bumps...) emitted username "" — a violation of the session-413
  unified full-row law and the seam the search front needs (a username-matched
  row would lose its handle on the first chat_updated). Fix: c.username into
  the SELECT + scan. Test red->green:
  TestChatRowWireCarriesUsername (SyncChats a dialog with Username "devcrew"
  -> REAL read-state HandleUpdate -> captured chat_snapshot AND chat_updated
  bytes both decode username=devcrew). Red seen first: 'chat_updated must
  carry the full row's username: got "", want devcrew' (the snapshot leg
  already passed — GetChatList always selected it).
- Gates: quick gate GREEN (scoped: bootstrap, engine, tests/bootstrap,
  tests/engine 6.3s, appport + window + cmd via windows vet), gofmt clean,
  comment ban clean (376 files).

- Atomic 2 (search matches usernames — the reference's fillNames seam 1/2,
  tdesktop data_peer.cpp fetched this session): the row search index gains the
  username — NameWords(name, username) []string + MatchesNameWords(index,
  words) replace MatchesWords (one law, one API; the name-only signature
  cannot express the row's searchable identity); SearchWords stays (query
  side — the reference splits '@' as a word splitter, so '@bob' IS a username
  query). Entry.Username; snapshotChat decodes json:"username" (the wire
  carried it since GetChatList — the app dropped it); the filter projects
  through NameWords. Red->green, red seen on the CURRENT code first:
  TestSearchFilterMatchesUsername (wire rows Alice/@alice, Bob/@bobby,
  Carol/- -> 'bobby' -> [Bob]: got [] before the change); + dialogs-level
  pins TestNameWordsUsernameLaw (10 cases: username-only/name-only queries,
  '@' split, AND-law across name+username, prefix miss, dedup) +
  TestNameWordsDedup; the prefix-law table reshaped to the new API with
  identical assertions.
- Gates (atomic 2): quick gate GREEN (scoped: tests/engine 6.4s, tests/gui,
  tests/ui, ui/dialogs, ui/history native; ui/app + renders + window + cmd
  via windows vet), gofmt clean, comment ban clean (376 files).

- Atomic 3 (the reference matching law completes — translit + keyboard
  layout, fillNames seams 2/3, tdesktop core/utils.cpp + data_peer.cpp
  fetched this session): translitRusEng (the 5 word overrides + 6
  double-letter pairs + the full single-letter Cyrillic map, ported
  verbatim), rusKeyboardLayoutSwitch (eng<->rus AND eng<->ukr row maps,
  32 positions incl. the [] ;' , . slots, both cases both directions; rus
  == ukr -> single variant, else both space-joined), hasRussianLetters
  ([а-яА-ЯёЁ]); NameWords = words of [folded name, translit if Cyrillic,
  username] + the layout switch of the whole joined string — the reference
  compounding pinned (Дима -> translit 'Dima' -> switch 'вшьф', so a
  wrong-layout query matches both the Cyrillic row and its Latin twin).
  BONUS BUG FOUND + FIXED (pre-existing, session-411): foldAccents was
  NFD+Mn-strip — it destroyed й (breve) -> и and, per the reference's own
  RemoveOneAccent table (case 1105), DIVERGED on ё (ours kept it, the
  reference folds ё->е BEFORE translit — 'Соловьёв' indexes 'solovyev'
  through the ье->ye double, not 'solovyov'). Replaced with removeAccents,
  a mechanical 1:1 port of lib_ui's RemoveOneAccent table (695 entries
  extracted programmatically from the fetched source — zero hand-typing) +
  the IsDiacritic drop law (Mn + U+0674 + U+FC7E-FC89); й survives, ё
  folds, Latin accents fold, unmapped scripts pass through. Red->green:
  TestNameWordsTranslitLaw + TestNameWordsKeyboardLayoutLaw (index pins
  incl. the ukr divergent slots ъ/ы/э <-> ї/і/є: 'S' -> ы AND і) +
  TestSearchFilterTranslitAndLayout (driven journeys: 'dima' -> [Дима,
  Dima], 'ghbdtn' -> [Привет Мир], 'lbvf' -> [Дима], 'вшьф' -> [Дима,
  Dima]); red seen: NameWords("Дима","") = [дима] want dima inside;
  NameWords("Привет","") = [привет] want ghbdtn; gui 'dima' -> [Dima].
  The username-law dedup pin updated in-commit to the full index law
  (NameWords("Alice Smith","alice") = [alice smith фдшсу ыьшер іьшер] —
  Smith's s hits the divergent slot). NOTE: the й-breve corruption was
  invisible before this session because nothing indexed Cyrillic names.
- Gates (atomic 3): quick gate GREEN (scoped: tests/engine 6.3s, tests/gui,
  tests/ui, ui/dialogs, ui/history native; renders + window + cmd via
  windows vet), js/wasm full-tree build green, gofmt clean, comment ban
  clean (376 files).

- Atomic 4 (the exact-'@' mentions mode — the reference inner widget
  4414-4417, fetched this session: filter == "@" switches to a mentions
  list, any other query rides the word law): setDialogRows filters to
  mention rows (unread_mention_count > 0 through the wire -> Entry.Mention)
  when Search.Text is exactly "@" — the honest local form of the reference
  mode (its server-side global results + sections ride the sections front);
  "@@" / " @" / "@word" stay word queries ("@" splits away, exactly the
  reference's PrepareSearchWords). Red->green:
  TestSearchFilterAtSignMentionsMode (rows Alice/-, Bob/1 mention,
  Carol/3 mentions: '@' -> [Bob Carol] — got [Alice Bob Carol] before;
  clear -> all; '@@' -> all; '@a' -> [Alice]; ' @' -> all).
- Gates (atomic 4): quick gate GREEN (scoped: tests/engine 6.4s, tests/gui,
  tests/ui native; ui/app + window + cmd via windows vet), gofmt clean,
  comment ban clean (376 files). The search front's matching layer is
  COMPLETE (query split/fold + index: name/translit/username/layout-switch
  + the '@' mode); what rides the NEXT front: search-results sections
  (chats/contacts/global grouping) + the PaintComposeBar zero-callers
  residual + msg-level unread bars (read-position) + ChatPreloadTopRequested
  no-op.

## Session 414 — D-3 closed in two atomics: engine decoupling + the raw-TCP js exclusion (2026-11-10)

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
- Atomic 2 (the exclusion): the six raw-TCP families tagged
  //go:build !js — telegram.go, telegram_dice/stats/stream/savedmusic/
  notify_sound/proximity, irc.go, xmpp.go, deltachat.go, teamspeak.go,
  mumble.go (dtls_native + calls_debug already carried it); the two
  now-dead js variants deleted (telegram_dtls_js.go 130 B,
  telegram_calls_debug_js.go 72 B — no-op siblings of !js files,
  dead everywhere after the family cut). Fallout fixed in-run: the
  shared telegram_data.go referenced InlineBotResult (telegram.go) +
  StatsValue/StatsGraphData (telegram_stats.go) — moved into the island
  (pure structs); cores/proxy.go was untagged and dragged 17 gotd
  packages through dcs/mtproxy — split: the shared ProxyConfig +
  active() stay untagged, the MTProxy machinery (resolver/dialFunc/
  httpConnectDialFunc/bufferedConn, sole caller telegram.go) moved to
  cores/telegram_proxy.go (!js). bootstrap split: factory_native.go
  (!js, the full 9-case switch + vaultSessionStorage + the gotd session
  import, byte-spliced from bootstrap.go) / factory_js.go (js,
  webPlatforms trio + honest default error "platform %q cannot connect
  from a browser"); bootstrap.go keeps the productPlatforms list — the
  account sweep rides it, so the js build NEVER deletes an account of a
  build-excluded platform (build exclusion is not deprecation; a raw-TCP
  account in the web-local vault starts with the honest factory error).
  SupportedPlatforms() is per-build: js = [github matrix bale] (order
  pinned). No per-core js stubs — dead code on js by construction;
  the factory error tells the truth instead.
- Tests (atomic 2) red->green, both seen RED first: tests/webbuild NEW —
  platforms_js_test.go (//go:build js; the trio pin under the wasm
  runner — run 1 printed got [telegram matrix irc xmpp github bale
  deltachat teamspeak mumble]) + family_tags_test.go (!js; source scan:
  every telegram*/irc/xmpp/deltachat/teamspeak/mumble file in cores
  except the telegram_data.go island must open with //go:build !js —
  run 1 printed "deltachat.go ... not excluded"; + the bootstrap
  factory_native/factory_js first-line pins + bootstrap.go gotd-free).
  All existing suites green zero re-pins: tests/cores 59.0s,
  tests/engine 7.0s, tests/bootstrap 1.1s, tests/webbuild, js legs:
  tests/webbuild + tests/audio (0.74s regression).
- Evidence (atomic 2): js link graph — GOOS=js go list -deps
  ./cmd/uniclient: gotd 0 packages (was 17 before the proxy split;
  mumble/xmpp/deltachat/teamspeak/irc SDKs 0); wasm plain-flag build
  (the WORKLOG precedent shape — session-412 numbers were plain-flag;
  CI's build.yml web job adds -trimpath -ldflags "-s -w" on runners
  with disk) = 26,714,844 B vs 32,837,371 B (session 412) =
  -6,122,527 B (-18.6%); the <20 MB projection from the open item did
  NOT hold — the honest remaining bulk is the web trio's own deps
  (mautrix+goolm 28 pkgs, bale gRPC-web, pion webrtc for group calls)
  + the rebuilt GUI (gioui 39 pkgs + gofonts) — the floor for the
  current feature set; 100 MB gh-pages ceiling headroom restored.
  dev-test.sh js leg + gate.sh quick js routing extended to
  tests/webbuild.
- Machine notes: /tmp+rootfs hit 99% full twice (the trimpath re-key
  recompiles everything; the windows cross attempt OOM'd gotd as
  documented §9 rung 7) — /tmp/go-build* pruned between legs; the
  plain-flag build rides the warm cache.
- Gates: quick gate GREEN (js leg now includes tests/webbuild: vet +
  wasm-runner run + the runner self-test), gofmt clean, comment ban
  clean (376 files), js/wasm full-tree build green, native pure build
  green, windows cmd cross-build blocked by the /tmp disk ceiling
  (rung 7 — CI verify cross-build is the gate).
- Next: W-2 residuals (search front: transliteration/username/
  "@"-mentions matching + search-results sections; PaintComposeBar
  zero callers).
