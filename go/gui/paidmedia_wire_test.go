package gui

// tests-first for BUGS.md B-12 — the paid-media star wall must actually
// render INSIDE the bubble and arm the unlock confirm card on click.
//
// Slice 181 built the whole chain (wall layout, confirm card, engine
// UnlockPaidMedia) and parity row 153 marked it PRESENT — but
// `layoutPaidMediaWall` was never called from any dispatch (git -S
// shows one commit: the file's own), so users never saw a wall, a
// price, or an unlock button. This test drives the REAL dispatch
// (messageRow) through the real layout + the real router, and clicks
// until the confirm card is armed: RED before the wiring.
//
// The button's exact rect is layout math we refuse to hard-code, so the
// click is a sweep over the frame — if the wall rendered, some press
// lands on it.

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

// paidWallTestMsg builds a locked (or unlocked) paid-media cached
// message with the Extra shape parsePaidMedia expects.
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

// clickEverywhere sweeps press/release pairs over the star-wall zone
// until stop() reports the click landed (or the grid runs out). The
// button's exact rect is layout math we refuse to hard-code — but the
// zone is bounded deliberately: the wall occupies the bubble's top
// (preview ≤360dp + button row ≈ y 376..410 at the default 0.75 wide
// factor), and staying inside it keeps the sweep off unrelated chrome
// whose handlers want a live engine (this test's App has none).
func clickEverywhere(t *testing.T, a *App, r *input.Router, ops *op.Ops,
	gtx layout.Context, f frame, m *engine.CachedMessage, stop func() bool) {

	t.Helper()
	// Layout of ANY row fires loadFavoriteReaction (chat.go corner-pill
	// setup), which spawns an engine call — favAttempted short-circuits
	// it. The favorite fetch is not this test's subject; without the
	// seed the goroutine derefs the nil engine and kills the binary.
	favMu.Lock()
	favAttempted[m.AccountID] = true
	favMu.Unlock()

	// Frame 1 registers the handlers the router will dispatch to.
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

// TestPaidWallRendersInBubbleAndArmsConfirm: a locked paid post's
// bubble must show the star wall, and pressing its Unlock button must
// arm the confirm card with the message's price.
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

// TestPaidWallAbsentWhenUnlockedOrNotPaid: the wall may never swallow
// unlocked paid media or ordinary messages (§1.10 — the real bubble
// must render once the server says paid_unlocked).
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
