# telegram_desktop_ui.md — Outstanding Spec Gaps

Source: full end-to-end audit of `research/telegram_desktop_ui.md` (session 2026-04-18). Each entry cites a line number in the audited file. After every content fill, strike through the entry (`~~line N~~`) and note the new subsection added. Rework line numbers if major blocks get re-inserted.

Progress so far:
- ✅ §1 reorder: §41/§42/§43 now in file order; §45/§46 swapped to correct order.
- ✅ §37 heading: HTML entities normalized to `§37 — Desktop Notifications`.
- ✅ §50 Streamer Mode & Read Toggles (AyuGram) added.
- ✅ §56 Appendix A — Resolved Style Constants added (~90 tokens resolved, ~25 still need deeper grep).
- ✅ §57 Appendix B — Dark Theme Color Palette added (full day-blue / night tables).
- ✅ §32.15 Story Creation Editor rewritten (300 lines, 13 subsections, honest gaps flagged where desktop source lacks features).
- ✅ §34.17 Create Conference Call Box added (287 lines — documents the participant picker + invite-link flow; clarifies that title/schedule/record options don't exist at creation time in upstream).
- ✅ §1 gaps filled: Shadow Separators subsection + Adaptive Width Formula (three-column shrink algorithm) + Linux Titlebar (X11/Wayland/KDE/GNOME) subsection.
- ✅ §2 gaps filled: search-mode tabs dimensions, stories ring gradient (confirmed no premium variant), unread/mention/reaction badge metrics, dark-theme hover/active/ripple palette, archived row (collapsed row, 37px, always-muted badge), swipe quick-action spec.
- ✅ §3 gaps filled: profile cover dimensions, account-switcher rows (26px avatar + active-ring), menu row metrics (`mainMenuButton` padding + font + icons), night-mode toggle widget, footer (two-line FlatLabel + tooltip).
- ✅ §4 gaps filled: topBarBg resolved (aliases windowBg in both themes, no distinct tint), 42px avatar in 52×54 hit-area, right-side buttons chrome (topBarSearch 40×54 + 40px ripple), 44px menu toggle, 49px pinned bar (32px thumb + 2×36 accent stripe + historyPinnedBg hex), contact status action bar (flat FlatButtons with historyContactStatusMinSkip=16), selection mode (easeOutCirc 200ms, uppercase button labels, RoundButton numbers animation, setCornerRadii pill).
- ✅ §5 gaps filled: JumpDownButton metrics (52×62 hit + 42px disc, 480px show threshold, 150ms slide), date badge (msgServicePadding + msgServiceBg alpha per theme), bubble colors resolved (all 8 tokens × day/night — night shadows disabled), bottom info row (font, icon sizes, inverted-overlay rules), peer name palette (8 slots × day/night hex + confirmed 64-extended fetched from server via help.peerColors), selection checkbox (20px, 160ms with bgDuration 0.75, boxTextFgGood), service-message pill (radius = height/2, text style).
- ✅ §6 gaps filled: spoiler particles (3000/128px, 1.5-2px, 60 frames @ 33ms, 200ms reveal), album layouter formula (complete dispatch rules + ComplexLayouter scoring), stickers (no shadow, 1.49× premium, mirror direction based on !rightAligned), voice waveform (100 fixed samples, full colors, no cursor line, 30% hover overlay), round video arc (3px stroke inset, 12 o'clock start, clockwise via negative sweep), polls (18px radio, 400ms quiz shake at ±3° linear, fireworks particle counts + colors), live location ring (28px, 2px stroke, counter-clockwise, no pulsing dot), web preview (article/standard NOT pixel-driven — webpage type only, no YouTube-specific overlay).

Session-handoff rule: pick any one of the section groups below, spawn parallel research agents (3+ at a time), and fill in. Each fill should be committed separately for clean history.

---

## §1–§13 — Core UI (primary target for next session)

Audit found dark-theme variants for almost every token are missing. §57 appendix now covers the palette — cross-reference it when filling these. Remaining structural gaps:

- ~~§1 (line 23): shadow-separator opacity; (line 31) shrink formula <932px; (line 37) Wayland/KDE titlebar rules.~~ **DONE** — Column Shadow Separators subsection, Responsive Breakpoints expanded with shrink formula, Linux Titlebar subsection.
- ~~§2 (line 62): search-focused tabs/chips dimensions; (line 68) stories ring gradient stops; (line 76) unread/mention/reaction badge metrics; (line 86) dark-theme hover/active; (line 91) archived row visual; (line 101) swipe quick action spec.~~ **DONE** — all six gaps filled with source-verified metrics.
- ~~§3 (lines 110, 115, 131, 134, 151): profile area dims, account-switcher rows, menu row metrics, night-mode toggle widget, footer styling.~~ **DONE** — Profile cover dims, Account section (26px avatar + 2px active ring), Menu row metrics (`mainMenuButton`), Night-mode toggle, Footer (two FlatLabels + tooltip).
- ~~§4 (lines 159, 166, 175, 185, 189, 197): topBarBg resolved, avatar size, right-side buttons, pinned-msg bar, action bar, selection mode.~~ **DONE** — all six gaps filled; cited `info.style`, `chat_helpers.style`, `ui/chat/message_bar.cpp`, theme palettes.
- ~~§5 (lines 207, 210, 219, 241, 245, 249, 253): jump-down + mentions buttons, date badge font/bg, bubble colors, info row metrics, peer-name palette hex (cross-ref §57.6), selection checkbox, service message pill radius/opacity.~~ **DONE** — full resolved bubble + service-bg color tables (day/night); JumpDownButton geometry + slide; selection checkbox (20px, 160ms); peer palette confirmed server-fetched for indices 8..63.
- ~~§6 (lines 265, 273, 287, 291, 295, 307, 311, 319): photo spoiler particles, album layouter formula, sticker shadows, voice waveform, round-video arc, polls radio/quiz shake, live-location ring, web preview thresholds.~~ **DONE** — spoiler animation descriptor (3000 particles / 60 frames @ 33ms), full grouped-layout algorithm, fireworks particle counts + colors, quiz shake ±3° linear 400ms, confirmed no YouTube-specific overlay, confirmed no client-side pulsing-dot on live-location maps.
- §7 (lines 327, 333, 343, 349, 365, 369, 373): compose strip dims, attach dropdown, send button anims, voice-record bar, bot keyboard, drag overlay, send-files dialog.
- §8 (lines 408, 409, 411, 420, 431): cover compression math, action button row, shared media buttons, members row, grid columns formula.
- §9 (lines 449, 473, 494, 498, 504): context menu chrome, attention-style color, reaction strip, forward dialog, delete confirmation.
- §10 (lines 512, 516, 524, 528, 532, 536): panel bg/shadow, tab bar, skin-tone popup, pack footer, GIF masonry, inline emoji dropdown.
- §11 (lines 550, 556, 564, 572, 582, 588, 594): _next button states, QR code quiet zone, country picker, CodeInput cells, 2FA error color, reg avatar picker, cover gradient.
- §12 (lines 604, 610, 612, 623, 630, 635, 642, 646, 650): panel size, signal bars, encryption fingerprint, PIP drag, narrow/wide transition, blob ring formula, TopBar gradients, screen-share chooser, rating dialog.
- §13 (lines 656, 669, 676, 683): OneColumn slide, narrow-width thresholds, touch long-press ms, web visual diffs.

## §14–§19 — Settings

- §14 (705–912): cover height formula, nav row metrics, scale slider, bio counter, profile rows, accounts list, theme cards, cloud themes, stickers/messages subsections, advanced, premium/help footer.
- §15 (972–1113): volume slider label, per-type separator, tone row, ringtones box, monitor widget.
- §16 (1181–1384): cloud-password field widths, TTL radio, AutoLockBox, active sessions (de-dup with §19), EditPrivacyBox, forward preview bubble, Charge Stars slider, gifts toggles, ClearPaymentInfoBox, file-extensions input, SelfDestructionBox, blocked users empty state.
- §17 (1432–1545): ProxiesBox full, LocalStorageBox tick labels, AutoDownloadBox width, Window Title checkboxes, Linux close-behavior, system integration, PowerSavingBox, ANGLE/OpenGL restart, settingsUpdateToggle progress, experimental section.
- §18 (1568–1739): filter divider label font, FilterRowButton timings, icon-toggle anchoring, FilterChatsPreview scroll, color buttons, inviteLinkList row, icon picker panel, disabled row status, tab view threshold.
- §19 (1773–1930): Rename style, current-session gradient, other-sessions dividers, SessionInfoBox fields, Rename dialog, SelfDestructionBox radio, power-saving indent, automatic-mode overlay, LanguageBox translation toggles, MultiSelect, language row height.

## §20–§26 — Media / Wizards / Topics / Keyboard / Theming / Admin

- §20 (1960–2137): HiDPI matrix, toolbar more-menu contents, PiP snapping rules, group thumbs overflow, context menu structured table, geometry animation curve.
- §21 (2142–2220): Forum entry flow, userpic icon origin, username validation debounce/API, PublicLinksLimitBox, group toggles visuals.
- §22 (2264–2370): topic icon SVG shape, z-order/stacking, TopicsView separators, context menu conditional matrix, EditForumTopicBox icon panel.
- §23 (2456–2694): RTL layout, repeat-period menu visuals, processing-video tip shape, published toast exact px, silent indicator tooltip.
- §24 (2874–3109): account switching defaults contradiction, folder/pinned precedence, Ctrl+Tab overlay spec (critical), markdown table dialog UIs, support-mode visuals, settings UI dimension table.
- §25 (3166–3754): full palette dump (reference §57), colorizer Night clamp, colorize exclusion list, theme editor px, pattern intensity math, `ThemeAdjustedColor` sampling, per-chat theme chooser px, CloudListCheck dims.
- §26 (4004–4708): Direct-Messages star input UI, permission dependency graph, ManageDirect definition, transfer ownership steps, admin log quoted bubble, admin log event table, progress arc intervals, invite link pickers, empty-state roles, pixel dims table resolved, slowmode send-button countdown, anti-spam threshold.

## §27–§34 — Auth / Export / Bots / Stories / Contacts / Calls

- §27 (4794–4940): per-platform biometric APIs, multi-account lock layout, AutoLockBox custom input.
- §28 (5170–5621): Add*Field wrapper error ring, SentCodeField cells, Ui::CodeInput email, EmailConfirm step stack.
- §29 (5730–6017): Account Data checkbox indent, ChooseTimeWidget dims, progress row fonts, TAKEOUT_INVALID box.
- §30 (6127–6484): bot menu button width formula, Web App loading screen, game button states, Login URL Auth dialog, payments panel details.
- §31 (6679–6789): SavedMessagesTagBar widget, EditTagNameBox, Subsection Tabs width computation.
- §32 (7076–7405): Public badge, reply compose layout, views list menu, profile stories grid, ~~story creation editor~~ (**DONE** — §32.15 rewritten), reaction panel trigger.
- §33 (7528–7682): stories bar in contacts, country code picker, edit-contact cover overlay.
- §34 (7895–8099): date-group headers, Rate Call dialog, active-call top bar details, ~~Group::PrepareCreateCallBox~~ (**DONE** — §34.17 added).

## §35–§49 — States / Popups / Misc

- §35 (8152–8862): universal "resolve constants to px" for every subsection; skeleton row, shared-media empty, connection state widget.
- §36 (8877–9206): box scale/easing, color picker swatches, toast style, popup menu dims, tooltip arrow, calendar/time picker.
- §37 (9596–9911): sizing table px, reply input grow rules, hidden userpic placeholder, stack overflow rules.
- §38 — complete.
- §39 (10153–10279): button-bar spacing, blur debounce, scroll-to-zoom rule.
- §40 (10319–10465): shrink scale factor, SingleFilePreview icons, HD badge dims, album layout constants, drag-area cross-ref.
- §41 (10838–10951): EditLinkBox widths, EditCodeLanguageBox length, blockquote bar.
- §42 (11017–11116): tab pill dims, tab bar wrapping, right emoji px.
- §43 (10659–10681): sizing px, date-line icons.
- §44 — complete.
- §45 (11618–11697): cache atlas dims, ReactionPreview overlay, View Pack button.
- §46 (11368–11470): FieldHeader dims, WebPageType button bar.
- §47 (11726–11828): WriteRestricted dims, forbidden ripple/toast, slowmode countdown region.
- §48 — complete.
- §49 (12146–12233): JumpDownButton dims, sticky date header, corner buttons stack height.

## §51–§55 — AyuGram extensions

- §51 — complete (post-reorder).
- §52: saveForBots UI gating; deletedMark/editedMark customization paths; EditMarkBox dims; DB scope per-userId; context-menu matrix; passcode/DB-encryption link; per-chat exclusion list.
- §53: Repeat Message hint text; download path cross-ref; mid-download cancel; progress-bar error states; per-account scope note.
- §54: avatarCorners off-by-one; Material Switches tokens; context menu ordering; attach-menu-bots per-account reactivity; AI Editor popup spec; IconPicker widget; HideReactions parent behavior; channelBottomButton "with fallback"; Translation Provider Win/Linux; Peer ID default; **Filters semantics (regex syntax, match scopes, case sensitivity) — totally missing**; **Shadow Ban flow**; §54.13/§54.14 renumbering; Streamer Mode now in §50 — update cross-refs.
- §55 — complete.
