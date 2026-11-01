package gui

import (
	"encoding/json"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

type botKbdBtn struct {
	Text     string
	Type     string
	Data     string
	URL      string
	Query    string
	SamePeer bool
	ButtonID int
	CopyText string
}

type botKbd struct {
	Rows [][]botKbdBtn
}

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

func replyKbdActive(msgs []engine.CachedMessage) *botKbd {
	kbd, _, _, _ := activeReplyKbd(msgs)
	return kbd
}

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

func botKbdHint(placeholder, def string) string {
	if p := strings.TrimSpace(placeholder); p != "" {
		return p
	}
	return def
}

func botKbdComposerHint(f frame) string {
	_, _, ph, _ := activeReplyKbd(f.messages)
	return botKbdHint(ph, "Write a message…")
}

type botKbdAction struct {
	Kind    string
	Payload string
	Data    string
}

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
	default:
		return botKbdAction{Kind: "callback", Data: b.Data}
	}
}

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

func replyKbdRenderable(b botKbdBtn) bool {
	switch b.Type {
	case "text", "web_view", "simple_web_view":
		return b.Text != ""
	}
	return false
}

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

func (a *App) layoutInlineKeyboard(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	kbd := parseInlineKeyboard(m)
	if kbd == nil {
		return layout.Dimensions{}
	}
	growKbdPools(&a.inlineKbdBtns, kbd.Rows)
	for r := range kbd.Rows {
		for c := range kbd.Rows[r] {
			if a.inlineKbdBtns[r][c].Clicked(gtx) {
				a.botKbdExec(m, botKbdActionFor(kbd.Rows[r][c]))
			}
		}
	}
	return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rowFlexChildren(kbd, a.inlineKbdBtns, a)...)
	})
}

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

func (a *App) layoutReplyKeyboard(gtx layout.Context, f frame, kbd *botKbd, src *engine.CachedMessage) layout.Dimensions {
	if kbd == nil || src == nil {
		return layout.Dimensions{}
	}
	if a.replyKbdUsedFor == src.MsgID {
		return layout.Dimensions{}
	}
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
	growKbdPools(&a.replyKbdBtns, rendered.Rows)
	for r := range rendered.Rows {
		for c := range rendered.Rows[r] {
			if a.replyKbdBtns[r][c].Clicked(gtx) {
				b := rendered.Rows[r][c]
				if b.Type == "text" {
					a.sendText(b.Text)
					if a.replyKbdSingleUse {
						a.replyKbdUsedFor = src.MsgID
					}
				} else {
					a.botKbdExec(src, botKbdActionFor(b))
				}
			}
		}
	}
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rowFlexChildren(rendered, a.replyKbdBtns, a)...)
	})
}
