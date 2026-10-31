package gui

import (
	"testing"

	"uniclient/engine"
)

// R20: the meta-strip tick mapping was written against magic numbers that
// drifted from the engine status consts — Sending(1) drew a check mark, the
// read accent landed on Delivered(3), Read(4) drew the dim double-check, and
// a permanently Failed(5) send drew the DELIVERED double-check (a lost
// message looked delivered). The mapping is pinned status-by-status here.
func TestStatusTickKind(t *testing.T) {
	cases := []struct {
		status int
		want   tickKind
		note   string
	}{
		{engine.MsgStatusSending, tickSending, "sending = spinner, never a check"},
		{engine.MsgStatusSent, tickSent, "sent = single dim check"},
		{engine.MsgStatusDelivered, tickDelivered, "delivered = dim double check"},
		{engine.MsgStatusRead, tickRead, "read = ACCENT double check (not delivered's)"},
		{engine.MsgStatusFailed, tickFailed, "failed = error mark, never a check"},
	}
	for _, c := range cases {
		if got := statusTickKind(c.status); got != c.want {
			t.Errorf("statusTickKind(%d) = %v, want %v (%s)", c.status, got, c.want, c.note)
		}
	}
	// Unknown/zero (legacy rows): the honest glyph is "still working on it".
	if got := statusTickKind(0); got != tickSending {
		t.Errorf("statusTickKind(0) = %v, want tickSending for unknown status", got)
	}
}
