# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 385 — the GUI kit build (post-
  skeleton); the complex bubble paint leg landed
  as b91b7c9 (op model: per-part side-rounded
  fill + inverted flares as concave-cut squares,
  ServiceBubbleRadii fontH parameterization,
  painter wiring: per-line shape widths, raw-
  width badge anchor, ServicePill replaced by
  the degenerate parts walk); verify 42451027930
  SUCCESS at job AND step level — closed green
- next: Material icon assets (chat-type/send-
  state/pinned/mention/poll/TTL glyphs) to
  un-defer icon paint; scroll input for the chat
  leg (wheel/touch — dialogs kinetic laws
  apply); history selection/emoji richness as
  measured needs arise
- owner-waiting: none
- last-gate: quick GREEN (135 ui + 43 gui = 178
  PASS; windows-vet substitute for render/window/
  cmd); comment ban 304 clean; CI 42451027930
  success (3 jobs, all steps)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 385 — the complex bubble paint leg: op model + painter wiring (2026-11-08)

- VM survived the whole session (first since
  wipe #9); repo booted at 9c248ea == origin.
- Flare shape measured to the mask source:
  createInvertedCircleMask(2r) = filled square
  MINUS centered disc (style_core.cpp:164-178),
  quartered by PrepareInvertedCornerPixmaps
  (cached_round_corners.cpp:246-262); cut lands
  at the disc-center corner of each drawn
  quadrant — top-left flare cuts bottom-right,
  top-right cuts bottom-left, bottom-left cuts
  top-right, bottom-right cuts top-left; flare
  squares inv x inv at (x-inv,side-y)/(x+w,
  side-y), side-y = top or bottom-inv. Gio
  paths: MoveTo(neighbor1) ArcTo(cut corner as
  center, +-pi/2 by sweep) LineTo(opposite)
  Close; +pi/2 sweeps up->right->down->left
  (screen), the only -pi/2 is cut-bottom-right.
- Op model: per part ONE fill with side-rounded
  corners (10 where Rounded, 0 else) — Go-native
  equivalent of Ayu corner pixmaps + middle
  fill, identical coverage; then top flares
  (L,R), then bottom flares (L,R). No op
  overlaps (flares sit outside part rects).
- ServiceBubbleRadii(fontH): normal=(3+fontH+4)
  /2, inverted=fontH-normal, shrink=2*inv/3 —
  the 384 token consts are the fontH=13 case
  (invariant-tested). PartsFont walk generalizes
  heights+shrink to measured svcH (render leg
  measures real fonts; 13-delegation intact).
- Painter: shape() now collects per-line ends
  (lineEnds), shapeLineWidths clamps >=0; add
  decision on RAW widths (call site 784-788),
  CountServiceLineWidths normalizes, PartsFont
  at svcH; parts y translated by g.Top-
  marginTop (Ayu p.translate 790-799); badge
  anchors on RAW lineWidths.back() with lines
  count (818-836). ServicePill code path
  replaced — single line IS the degenerate parts
  walk (identical geometry; empty text now
  paints nothing, matching Ayu's zero-iteration
  loop). bubblePath refactored onto shared
  openCornersPath (tails unchanged).
- RED 8 tests -> 1 spec error (nil-vs-empty
  again; law won). GREEN 178 PASS (135 ui + 43
  gui). b91b7c9 -> verify 42451027930 success
  (3 jobs, all steps, job AND step reconciled).

## Session 384 — the multi-line service complex bubble law (2026-11-08)

- Boot: wipe #11. Clone at bcf2757 — 379-383
  closed green in lost sessions; baseline 159
  re-verified after env rebuild.
- Law source: history_view_service_message.cpp
  372-485 + chat_style.cpp 103-126 + call site
  780-798 (detail in git + service_bubble.go
  tests): radii 10/3/2 DERIVED from pad/font
  pins; CountServiceLineWidths minDelta-22
  neighbor raise + i-=2 rewalk + post-add;
  call-site add 9 iff clamped back > badge
  additional && < before; parts walk (richW
  +24, richH +3/-4/+4/-3 by sides, forceShrink
  on prevShrink+equal, shrink x+=2 w-=4, C++-
  trunc centering = Go native). RED 11 -> 2
  spec errors (law won). 170 PASS; e21f207;
  verify 42448242342 SUCCESS job+step.

## Session 383 — the message-bubble render leg: corner/tail/shadow laws, chat Elm + ChatPainter (2026-11-07)

- Boot: wipe #10 (skills/download/upload only).
  Clone at 8b2ae432 — 379-382 had closed green in
  lost sessions (127→141 baseline re-verified
  after toolchain/modcache/ayu-ref rebuild).
- Bubble corner law (message.cpp:6626-6651
  countMessageRounding, verbatim): attachedTop
  smalls the wall-side top corner, attachedBottom
  smalls the wall-side bottom corner, tail lands
  on the layout-side bottom (skipTail removes,
  keyboard overrides both bottoms to Small);
  Large=BubbleRadiusLarge()=16 Small=6 Tail->0
  (chat_style_radius.cpp map: slider 16 = max);
  Ayu removeMessageTail (default OFF) Tail->Large.
- Tail glyph 6x10 (bubble_tail.png, right-angle
  triangle, diagonal (6,0)->(0,10), wall-side
  vertical edge): left at (x-6, bottom-10), right
  at (right, bottom-10). Shadow strip 2px
  (msgShadow) below bottom between corner radii
  widened by tails; colors colors.palette RRGGBBAA
  in #748ea2@0x29 out #3ac346@0x1d.
- Service pill (single line): centered lineW+24
  x fontH+7, radius (3+h+4)/2 = pillH/2
  (chat_style.cpp:103). Ayu badge pos: x = trect.x
  + (trect.w-lastLineW)/2 + max(lastLineW-
  additional,0) + (lastTextW?8:0); y = trect.y +
  (lines-1)fontH + (fontH-badgeH)/2; bg black@0x1e.
- Time label (message.cpp:5479-5516 drawInfo):
  infoRight = right-(11-2), infoBottom = bottom-
  (8-5); text right-aligned there; out send-state
  icon consumes 24px, anchor (-17,-19) off
  (infoRight, textY+dateFontH).
- Chat mode: >= adaptiveChatWideWidth 880 (default
  adaptiveForWide=true) -> Wide (recountChatWidth
  chain pinned end-to-end). MessageContentWidth
  extracted as the shared clamp chain (Geometry/
  Height/painter all call one law now).
- Chat Elm leg: Item/List/Heights + measure-as-
  message (ChatLoaded nils heights + dirty,
  ChatMeasured refills + clamps, ChatScrolled/
  Resized clamp; zero-height viewport paints
  nothing — dialogs precedent won over my spec);
  ChatPane{Rows,Ys,Heights,View,First,Count};
  Scene.Chat; window measures-on-dirty before
  View, paints past the dialogs column.
- ChatPainter: shaper metrics with TD skip-block
  emulation (last line height max(fontH,skipH),
  extra line when lastEnd+skipW > width — matches
  TD height; body wrap approx: all-lines-narrow,
  documented for the text-engine slice), bubble
  path per-corner arcs + tail subpaths (nonzero
  outline, adjacent-not-overlapping), Material
  skin: in SurfaceContainerHigh/out Primary,
  pill InverseSurface/InverseOnSurface, fromName
  in Primary. 2 spec cases fell to the law
  (attached shadow width 178; scene top=80
  scenario). 18 tests, 159 total; shipped 4fdc467c,
  verify 42409023939 SUCCESS job+step.

## Session 382 — the history element geometry law: margins, bubble, service (2026-11-07)

- Boot: wipe #9 (only skills/download/upload; .env
  sweep clean). Clone at 874f707f — 379-381 had
  closed green in lost sessions (Elm+render leg,
  input leg, kinetic+overscroll; 127 baseline re-
  verified after toolchain/modcache/ayu-ref rebuild).
- Surface: element.cpp (skip block 1631-1650,
  textualMaxWidth 2940, DateBadge 857), message.cpp
  (margins 1708-1759, countGeometry 6557-6628,
  resizeContentGetHeight 6680-6935, bubbleTextWidth
  5668, monospaceMaxWidth 5648, optimal 1347),
  service_message.cpp (margins 667-696, geometry 540,
  height 565-640, ComputeServiceTimeMetrics ~500),
  chat.style (msgMinWidth 160, msgDateSpace 12,
  msgDateDelta 2/5), ayu_styles.style (time badge
  11px semibold pads 7/2 gap 8 inset 3).
- go/ui/history/element.go: message top margin =
  attached?0:6 + bars + servicePre-above + added —
  BARS SURVIVE HIDDEN (only the msg margin is
  conditioned); bottom = 2 + below-servicePre,
  hidden 0. Service: 10/2, servicePre UNCONDITIONAL
  (no below check), bottom pays even hidden.
  DateBadge 10+3+font+4+2. Skip block 12+infoW−2 /
  fontH−5. textW = max(w,160)−22; limit unlimited?
  0x3FFFFFF : max(430, mono). Geometry: left 16
  (rightLayout wideSkip; narrow 16) + photoSkip 40,
  rightAction −w−(40−31); clamps maxWidth → limit →
  shrunk max(realWidth+22, nonTextMax); out shift /
  centered halves; Wide centered max((430+80−w)/2,0).
  Height: ==maxWidth keeps OPTIMAL minHeight else
  heightFor(textW)+8+8; +fromName font; +needInfo
  bottomInfo−dateFont; + margins. Service height:
  TWO-SMALL-MARGINS quirk (−2×10), floor 25, nwidth
  max(cw−24,0), fits→minHeight else heightFor, empty
  text = marginTop−10; Wide min(w,542). Ayu time
  badge: w+14, h+4, additional max(w+13,0), skip
  max(badgeH, serviceFontH).
- Text engine deferred like icon paint: Text{MaxWidth,
  MinHeight, HeightFor(w)→(height, realWidth)};
  tests inject synthetic layouts.
- TDD: RED 14 undefined → GREEN 14 first run (2
  expectation slips caught at design time). 141
  total; gates clean. Shipped 3a655338; verify
  42384001792 SUCCESS at job AND step level — 382
  closed green.

## Session 381 — kinetic touch + overscroll anim: fling, rubber band, spring return (2026-11-07)

- Flick law (touchUpdateSpeed per-axis px/s),
  rubber-band overscroll (elastic_scroll.cpp,
  pins in dialogs kinetic code + tests),
  spring return anim; bar-drag overscroll
  range-clamp landed (deferred from 380).
  13 tests, 112 total; ac999d75; verify
  42372859307 SUCCESS job+step.

## Session 380 — the window-adapter input leg: wheel, hit-test, bar drag, touch (2026-11-07)

- Wheel law (ui_utility.cpp:268-288 + elastic_scroll
  :926-945, pins in dialogs/window code + tests):
  angle→px = angle×lines/(2×3) qRound'd; per-axis
  Ctrl/Shift mult max(w|h,120)/120 TRUNCATED (y by
  scroll HEIGHT); cross-axis |px|>=|py| ignores;
  dy = −pixels.y; pixel path qRound through the same
  block. Bar: 10dp-strip hit test, off-thumb press
  = jump-to-middle, drag dy×scrollable/outsideBar.
  Touch: manhattan>=10 arms 1:1 (arm swallows the
  crossing delta — 381 corrected), tap selects at
  release. 6 Elm messages + Model states; PaintPane
  event.Op; window pointer.Filter + Metric px→dp.
  18 tests, 99 total; e30bbfad; verify 42362009163
  SUCCESS job+step.

## Session 379 — the dialogs list Elm+render leg: viewport state, scroll laws, Pane snapshot, PaintPane (2026-11-07)

- Wheel apply = tryScrollTo(from+delta), delta =
  −pixels.y, rest clamp [0, content−view]; load-more
  on every viewport msg while loadTill >= content
  (empty list = initial page request — resize pin
  updated accordingly). dialogs.Pane + List.Pane(v,
  width) snapshot; Elm Model.DialogsScroll + clamp
  on Loaded/Resized; render.PaintPane (viewport
  clip, per-row offset, thumb rrect). 5 spec cases
  fell to the law. 9 tests, 81 total; shipped
  239cdaf1, verify 42351344419 SUCCESS job+step.

## Session 378 — wipe #5 boot + the dialogs list scroll law: viewport, virtualization, reveal, thumb (2026-11-07)

- Discovery: dialogs list = Ui::ElasticScroll
  (not ScrollArea) — thumb law elastic_scroll.cpp:
  131-175. dialogs/scroll.go: Viewport, MaxOffset/
  Clamp, VisibleRows (1px-overlap lower_bound +
  walk), PreloadWindow 3 screens, ScrollToReveal,
  Thumb (skip 6, thickness 4, barMin min(40,avail/
  2), hide rules, ratio cut-clamp). 12 tests, 72
  total; e38052c2; verify 42347578779 SUCCESS.

## Session 377 — the dialogs row widget: pure layout + Elm state + gio render (2026-11-07)

- dialogs Entry+Layout (name-rect shrink date+5 ->
  chat icon+3 -> send state -20; badge stack
  right-anchored max-2; variants 62/72/80/96; online
  43/43 TTL 36/36); Elm selection clamp; render
  Painter (bg states, photo/userpic, presence dot,
  elided labels, counter pill); icon glyphs
  deferred. 11 ui + 1 gui; gates clean.

## Session 376 — wipe #4 boot: env rebuilt; Material theme system (M3 baseline + AMOLED) (2026-11-07)

- ui/material Scheme 36 roles Light/Dark/Amoled
  (Compose material3 v0_210); dialogs-row slice 5
  pins; TTL-pos test caught a real porting bug.

## Session 375 — the Gio skeleton: Elm core, window adapter, the measured pane law; the cgo-closure fight (2026-11-06)

- go/ui/app Elm core (zero Gio) + pane law
  (computeColumnLayout); window adapter; gioui
  Xlib cgo closure -> gate.sh windows-vet
  substitute; flake green 75944429.

## Session 374 — geometry-table slice 4 re-mined after a full-wipe recycle (2026-11-06)

- Re-derivation converged 23/23; pins in tokens.go
  + tests; CI 42187083372 SUCCESS; T-2 closed.
