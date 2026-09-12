package gui

// botkbd.go — slice 127: bot keyboards (AyuGram/tdesktop parity row §4 118).
// The Telegram core has parsed ReplyInlineMarkup / ReplyKeyboardMarkup /
// ReplyKeyboardHide into message Extra since the callback work; this slice
// renders them:
//
//   - INLINE keyboards: button rows below the message content inside the
//     bubble (tdesktop HistoryView look). callback buttons fire
//     messages.getBotCallbackAnswer via engine.BotCallback (answer text as
//     toast, answer URL opens); game buttons callback with game=true; url /
//     url_auth / web_view / simple_web_view open in the platform browser
//     (WebApps need a webview — the system-browser handoff is the honest
//     pure-Go ceiling, same policy as the video player); copy buttons copy;
//     switch_inline same_peer inserts into the a.wid.composer, otherwise the
//     "@bot query" text goes to the clipboard (tdesktop switches chats via
//     a picker — honest approximation); buy explains itself (payments are
//     out of scope for this build).
//   - REPLY keyboards: a panel under the a.wid.composer for the chat's LATEST
//     keyboard-carrying message; keyboard_hide clears it; single_use hides
//     it after one tap; the markup's placeholder replaces the a.wid.composer
//     hint. Only buttons the app can act on render (text sends, web_view
//     opens); request_phone / request_location / request_poll /
//     request_peer are omitted rather than shown dead (§1.10).
//
// force_reply (ReplyKeyboardForceReply) is not wired: it only styles the
// a.wid.composer hint while a reply is pending, and the reply chip already
// communicates that state.

import (
	"encoding/json"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// ── model ──────────────────────────────────────────────────────────────────

// botKbdBtn is one parsed keyboard button (inline or reply). Types mirror
// the core's Extra contract (telegram.go convertMessage).
type botKbdBtn struct {
	Text     string
	Type     string // callback|url|url_auth|switch_inline|game|buy|web_view|simple_web_view|copy|text|request_*
	Data     string // callback payload
	URL      string
	Query    string // switch_inline
	SamePeer bool
	ButtonID int // url_auth
	CopyText string
}

// botKbd is a parsed keyboard: bot-defined rows of buttons.
type botKbd struct {
	Rows [][]botKbdBtn
}

// parseKbdBtn decodes one Extra button map.
func parseKbdBtn(v interface{}) botKbdBtn {
	bm, _ := v.(map[string]interface{})
	if bm == nil {
		return botKbdBtn{}
	}
	b := botKbdBtn{
		Text:     strings.TrimSpace(strVal(bm["text"])),
		Type:     strVal(bm["type"]),
		Data:     strVal(bm["data"]),
		URL:      strVal(bm["url"]),
		Query:    strVal(bm["query"]),
		SamePeer: bm["same_peer"] == true,
		CopyText: strVal(bm["copy_text"]),
	}
	if f, ok := extraNum(bm["button_id"]); ok {
		b.ButtonID = int(f)
	}
	return b
}

// parseKbdRows decodes the shared []rows value of both markup types.
func parseKbdRows(v interface{}) [][]botKbdBtn {
	rawRows, _ := v.([]interface{})
	var rows [][]botKbdBtn
	for _, rr := range rawRows {
		rawBtns, _ := rr.([]interface{})
		btns := make([]botKbdBtn, 0, len(rawBtns))
		for _, rb := range rawBtns {
			if b := parseKbdBtn(rb); b.Text != "" {
				btns = append(btns, b)
			}
		}
		if len(btns) > 0 {
			rows = append(rows, btns)
		}
	}
	return rows
}

// parseInlineKeyboard extracts the inline keyboard of a cached message
// (Extra["inline_keyboard"], written by the telegram core). nil when the
// message carries no usable markup.
func parseInlineKeyboard(m *engine.CachedMessage) *botKbd {
	if m == nil || len(m.ContentRaw) == 0 {
		return nil
	}
	var env rawEnvelope
	if err := json.Unmarshal(m.ContentRaw, &env); err != nil || env.Extra == nil {
		return nil
	}
	rows := parseKbdRows(env.Extra["inline_keyboard"])
	if len(rows) == 0 {
		return nil
	}
	return &botKbd{Rows: rows}
}

// parseReplyKeyboard extracts the custom reply keyboard of a cached message
// (Extra["reply_keyboard"]). nil keyboard when absent or empty; the
// single-use flag and placeholder come with it.
func parseReplyKeyboard(m *engine.CachedMessage) (kbd *botKbd, singleUse bool, placeholder string) {
	if m == nil || len(m.ContentRaw) == 0 {
		return nil, false, ""
	}
	var env rawEnvelope
	if err := json.Unmarshal(m.ContentRaw, &env); err != nil || env.Extra == nil {
		return nil, false, ""
	}
	rm, _ := env.Extra["reply_keyboard"].(map[string]interface{})
	if rm == nil {
		return nil, false, ""
	}
	rows := parseKbdRows(rm["rows"])
	if len(rows) == 0 {
		return nil, false, ""
	}
	return &botKbd{Rows: rows}, rm["single_use"] == true, strVal(rm["placeholder"])
}

// replyKbdActive reports whether the loaded window leaves a reply keyboard
// active (thin wrapper over activeReplyKbd; the a.wid.composer wiring needs the
// full tuple).
func replyKbdActive(msgs []engine.CachedMessage) *botKbd {
	kbd, _, _, _ := activeReplyKbd(msgs)
	return kbd
}

// activeReplyKbd resolves the open chat's reply-keyboard panel state from
// its loaded messages (oldest→newest, like a.messages): the LATEST keyboard
// wins; a plain message keeps the previous panel; a later keyboard_hide
// clears it (tdesktop semantics — bots dismiss the panel with
// reply_keyboard_hide). Returns the keyboard, its single_use flag, its
// placeholder, and the carrying message (kbd nil when no panel).
func activeReplyKbd(msgs []engine.CachedMessage) (kbd *botKbd, singleUse bool, placeholder string, src *engine.CachedMessage) {
	var active *botKbd
	var srcMsg *engine.CachedMessage
	var su bool
	var ph string
	for i := range msgs {
		m := &msgs[i]
		if m.IsService || len(m.ContentRaw) == 0 {
			continue
		}
		var env rawEnvelope
		if err := json.Unmarshal(m.ContentRaw, &env); err != nil || env.Extra == nil {
			continue
		}
		if env.Extra["keyboard_hide"] == true {
			active, srcMsg, su, ph = nil, nil, false, ""
			continue
		}
		if rm, _ := env.Extra["reply_keyboard"].(map[string]interface{}); rm != nil {
			if rows := parseKbdRows(rm["rows"]); len(rows) > 0 {
				active, srcMsg = &botKbd{Rows: rows}, m
				su = rm["single_use"] == true
				ph = strVal(rm["placeholder"])
			}
		}
	}
	return active, su, ph, srcMsg
}

// botKbdHint picks the a.wid.composer hint: the reply keyboard's placeholder when
// present, the default otherwise.
func botKbdHint(placeholder, def string) string {
	if p := strings.TrimSpace(placeholder); p != "" {
		return p
	}
	return def
}

// botKbdComposerHint resolves the a.wid.composer hint for a frame: the active
// reply keyboard's placeholder (tdesktop) or the default text.
func botKbdComposerHint(f frame) string {
	_, _, ph, _ := activeReplyKbd(f.messages)
	return botKbdHint(ph, "Write a message…")
}

// ── actions ────────────────────────────────────────────────────────────────

// botKbdAction is the pure classification of a button tap; the executor
// (botKbdExec) turns it into engine/GUI calls. Pure so it is unit-tested.
type botKbdAction struct {
	Kind    string // callback|game|url|copy|insert|clipboard|unsupported
	Payload string // URL / copy text / insert text / clipboard text
	Data    string // callback data
}

// botKbdActionFor classifies an inline-keyboard button.
func botKbdActionFor(b botKbdBtn) botKbdAction {
	switch b.Type {
	case "game":
		return botKbdAction{Kind: "game"}
	case "url", "url_auth", "web_view", "simple_web_view":
		return botKbdAction{Kind: "url", Payload: b.URL}
	case "copy":
		return botKbdAction{Kind: "copy", Payload: b.CopyText}
	case "switch_inline":
		if b.SamePeer {
			return botKbdAction{Kind: "insert", Payload: b.Query}
		}
		return botKbdAction{Kind: "clipboard", Payload: b.Query}
	case "buy":
		return botKbdAction{Kind: "unsupported"}
	default: // "callback" and the core's unknown-button default
		return botKbdAction{Kind: "callback", Data: b.Data}
	}
}

// botKbdExec performs a classified button action (runs the engine call on a
// background goroutine; toasts land back on the GUI loop).
func (a *App) botKbdExec(m *engine.CachedMessage, act botKbdAction) {
	switch act.Kind {
	case "callback", "game":
		acct, chat, msg := m.AccountID, m.ChatID, m.MsgID
		data, isGame := act.Data, act.Kind == "game"
		go func() {
			res, err := a.eng.BotCallback(acct, chat, msg, data, isGame)
			if err != nil {
				a.setToast("Button error: " + err.Error())
				return
			}
			if res.URL != "" {
				a.openLinkExternal(res.URL)
				return
			}
			if res.Message != "" {
				if res.ShowAlert {
					a.setToast("Bot: " + res.Message)
				} else {
					a.setToast(res.Message)
				}
				return
			}
			a.setToast("Done")
		}()
	case "url":
		if act.Payload == "" {
			a.setToast("Button has no link")
			return
		}
		a.openLinkExternal(act.Payload)
	case "copy":
		if act.Payload == "" {
			return
		}
		a.copyTextSoon(act.Payload)
		a.setToast("Copied")
	case "insert":
		if act.Payload == "" {
			return
		}
		a.wid.composer.Insert(act.Payload + " ")
	case "clipboard":
		if act.Payload == "" {
			return
		}
		a.copyTextSoon(act.Payload)
		a.setToast("Copied — paste it in the chat you want")
	case "unsupported":
		a.setToast("Payments are not available in this build")
	}
}

// replyKbdRenderable gates which reply-keyboard button types act in this
// build (see file comment): text sends, the two webview variants open their
// URL. request_* types need native pickers/flows not built yet — omitted
// rather than rendered dead (§1.10).
func replyKbdRenderable(b botKbdBtn) bool {
	switch b.Type {
	case "text", "web_view", "simple_web_view":
		return b.Text != ""
	}
	return false
}

// ── widgets ────────────────────────────────────────────────────────────────

var (
	inlineKbdBtns [][]widget.Clickable // per-row button pools
	replyKbdBtns  [][]widget.Clickable

	// Reply-keyboard session state (package-level like the other a.wid.composer
	// chrome; touched only on the GUI goroutine).
	replyKbdSingleUse bool   // the active keyboard is single_use
	replyKbdUsedFor   string // msgID whose single_use keyboard was consumed ("" = none)
)

// growKbdPools keeps one Clickable pool per row count.
func growKbdPools(pool *[][]widget.Clickable, rows [][]botKbdBtn) {
	for len(*pool) < len(rows) {
		*pool = append(*pool, nil)
	}
	*pool = (*pool)[:len(rows)]
	for r := range rows {
		for len((*pool)[r]) < len(rows[r]) {
			(*pool)[r] = append((*pool)[r], widget.Clickable{})
		}
		(*pool)[r] = (*pool)[r][:len(rows[r])]
	}
}

// botKbdButton lays out one keyboard button: filled rounded rect, centered
// label. URL-ish buttons tint like links; callback/game buttons use the
// accent color (tdesktop styling split).
func (a *App) botKbdButton(gtx layout.Context, cl *widget.Clickable, b botKbdBtn) layout.Dimensions {
	btn := material.Button(a.ui.Theme, cl, b.Text)
	btn.CornerRadius = 8
	btn.Inset = layout.UniformInset(unit.Dp(10))
	btn.TextSize = unit.Sp(14)
	switch botKbdActionFor(b).Kind {
	case "url":
		btn.Background = a.ui.p.AccentDim
	default:
		btn.Background = a.ui.p.Accent
	}
	return btn.Layout(gtx)
}

// layoutInlineKeyboard renders the message's inline keyboard below the
// bubble content: bot-defined rows, buttons sharing the row width evenly.
func (a *App) layoutInlineKeyboard(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	kbd := parseInlineKeyboard(m)
	if kbd == nil {
		return layout.Dimensions{}
	}
	growKbdPools(&inlineKbdBtns, kbd.Rows)
	for r := range kbd.Rows {
		for c := range kbd.Rows[r] {
			if inlineKbdBtns[r][c].Clicked(gtx) {
				a.botKbdExec(m, botKbdActionFor(kbd.Rows[r][c]))
			}
		}
	}
	return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rowFlexChildren(kbd, inlineKbdBtns, a)...)
	})
}

// rowFlexChildren builds the per-row horizontal flex (buttons split the row
// width evenly, tdesktop keyboard look).
func rowFlexChildren(kbd *botKbd, pool [][]widget.Clickable, a *App) []layout.FlexChild {
	children := make([]layout.FlexChild, 0, len(kbd.Rows))
	for r := range kbd.Rows {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				var rowChildren []layout.FlexChild
				for c := range kbd.Rows[r] {
					btn := kbd.Rows[r][c]
					cl := &pool[r][c]
					rowChildren = append(rowChildren, layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return a.botKbdButton(gtx, cl, btn)
					}))
				}
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, rowChildren...)
			})
		}))
	}
	return children
}

// layoutReplyKeyboard renders the reply-keyboard panel under the a.wid.composer
// (the chat's active keyboard). Taps act on the button; single_use marks
// the keyboard consumed so the panel disappears.
func (a *App) layoutReplyKeyboard(gtx layout.Context, f frame, kbd *botKbd, src *engine.CachedMessage) layout.Dimensions {
	if kbd == nil || src == nil {
		return layout.Dimensions{}
	}
	if replyKbdUsedFor == src.MsgID {
		return layout.Dimensions{} // single_use consumed
	}
	// Keep only actionable rows; a keyboard whose rows all drop is not shown.
	rows := make([][]botKbdBtn, 0, len(kbd.Rows))
	for _, r := range kbd.Rows {
		keep := make([]botKbdBtn, 0, len(r))
		for _, b := range r {
			if replyKbdRenderable(b) {
				keep = append(keep, b)
			}
		}
		if len(keep) > 0 {
			rows = append(rows, keep)
		}
	}
	if len(rows) == 0 {
		return layout.Dimensions{}
	}
	rendered := &botKbd{Rows: rows}
	growKbdPools(&replyKbdBtns, rendered.Rows)
	for r := range rendered.Rows {
		for c := range rendered.Rows[r] {
			if replyKbdBtns[r][c].Clicked(gtx) {
				b := rendered.Rows[r][c]
				if b.Type == "text" {
					a.sendText(b.Text)
					if replyKbdSingleUse {
						replyKbdUsedFor = src.MsgID
					}
				} else {
					a.botKbdExec(src, botKbdActionFor(b))
				}
			}
		}
	}
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rowFlexChildren(rendered, replyKbdBtns, a)...)
	})
}
