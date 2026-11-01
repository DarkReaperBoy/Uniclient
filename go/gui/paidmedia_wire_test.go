package gui

import (
	"image"
	"testing"

	"gioui.org/f32"
	"gioui.org/io/input"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"

	"uniclient/engine"
)

func paidWallTestMsg(msgID string, unlocked bool) *engine.CachedMessage {
	raw := `{"extra":{"invoice_is_paid_media":true,"paid_stars":25,"paid_w":800,"paid_h":600`
	if unlocked {
		raw += `,"paid_unlocked":true`
	}
	raw += `}}`
	return &engine.CachedMessage{
		AccountID:  "a1",
		ChatID:     "c1",
		MsgID:      msgID,
		ContentRaw: []byte(raw),
	}
}

func clickEverywhere(t *testing.T, a *App, r *input.Router, ops *op.Ops,
	gtx layout.Context, f frame, m *engine.CachedMessage, stop func() bool) {

	t.Helper()
	favMu.Lock()
	favAttempted[m.AccountID] = true
	favMu.Unlock()

	a.messageRow(gtx, f, m)
	r.Frame(ops)

	for y := 330; y < 430 && !stop(); y += 20 {
		for x := 120; x < 490 && !stop(); x += 20 {
			pos := f32.Pt(float32(x), float32(y))
			r.Queue(
				pointer.Event{Kind: pointer.Press, Source: pointer.Mouse,
					Buttons: pointer.ButtonPrimary, Position: pos},
				pointer.Event{Kind: pointer.Release, Source: pointer.Mouse,
					Buttons: pointer.ButtonPrimary, Position: pos},
			)
			a.messageRow(gtx, f, m)
			r.Frame(ops)
		}
	}
}

func TestPaidWallRendersInBubbleAndArmsConfirm(t *testing.T) {
	a := &App{ui: NewUI()}
	a.wid.init()

	var r input.Router
	var ops op.Ops
	gtx := layout.Context{
		Ops:         &ops,
		Source:      r.Source(),
		Constraints: layout.Exact(image.Pt(800, 600)),
	}
	m := paidWallTestMsg("paid1", false)
	f := frame{msgFor: &chatKey{AccountID: "a1", ChatID: "c1"}}

	clickEverywhere(t, a, &r, &ops, gtx, f, m, func() bool { return a.paidDlg != nil })

	if a.paidDlg == nil {
		t.Fatal("paid wall never armed the unlock confirm — the star wall is not wired into the bubble (B-12)")
	}
	if a.paidDlg.stars != 25 {
		t.Errorf("confirm stars = %d, want 25", a.paidDlg.stars)
	}
	if a.paidDlg.msgID != "paid1" {
		t.Errorf("confirm msgID = %q, want paid1", a.paidDlg.msgID)
	}
}

func TestPaidWallAbsentWhenUnlockedOrNotPaid(t *testing.T) {
	for _, tc := range []struct {
		name string
		msg  *engine.CachedMessage
	}{
		{"unlocked paid media", paidWallTestMsg("paid2", true)},
		{"plain text message", &engine.CachedMessage{
			AccountID: "a1", ChatID: "c1", MsgID: "plain1",
			ContentText: "hello",
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			a := &App{ui: NewUI()}
			a.wid.init()

			var r input.Router
			var ops op.Ops
			gtx := layout.Context{
				Ops:         &ops,
				Source:      r.Source(),
				Constraints: layout.Exact(image.Pt(800, 600)),
			}
			f := frame{msgFor: &chatKey{AccountID: "a1", ChatID: "c1"}}

			clickEverywhere(t, a, &r, &ops, gtx, f, tc.msg, func() bool { return a.paidDlg != nil })
			if a.paidDlg != nil {
				t.Fatalf("confirm armed for %s — wall must not render here", tc.name)
			}
		})
	}
}
