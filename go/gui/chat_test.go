package gui

import (
	"testing"

	"uniclient/engine"
)

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
	if got := statusTickKind(0); got != tickSending {
		t.Errorf("statusTickKind(0) = %v, want tickSending for unknown status", got)
	}
}
