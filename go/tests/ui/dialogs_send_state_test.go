package tests

import (
	"testing"

	. "uniclient/ui/dialogs"
	. "uniclient/ui/icons"
)

func iconZero(i Icon) bool {
	return i.Glyph.W == 0 && i.Glyph.H == 0 && len(i.Glyph.Paths) == 0 && i.Cell == (Cell{})
}

func TestDialogsSendStateSelection(t *testing.T) {
	cases := []struct {
		state SendState
		want  Icon
	}{
		{SendHidden, Icon{}},
		{SendSending, DialogsSending},
		{SendSent, DialogsSent},
		{SendReceived, DialogsReceived},
	}
	for _, c := range cases {
		got := SendStateIcon(c.state)
		if c.state == SendHidden {
			if !iconZero(got) {
				t.Fatalf("SendStateIcon(%d) must be zero, got cell %dx%d", c.state, got.Cell.W, got.Cell.H)
			}
			continue
		}
		if iconZero(got) {
			t.Fatalf("SendStateIcon(%d) must resolve an icon, got zero", c.state)
		}
		if got.Cell != c.want.Cell {
			t.Fatalf("SendStateIcon(%d) = cell %+v, want %+v", c.state, got.Cell, c.want.Cell)
		}
		if got.Glyph.W != c.want.Glyph.W || got.Glyph.H != c.want.Glyph.H {
			t.Fatalf("SendStateIcon(%d) = glyph %dx%d, want %dx%d",
				c.state, got.Glyph.W, got.Glyph.H, c.want.Glyph.W, c.want.Glyph.H)
		}
	}
}

func TestDialogsBadgeKindsMentionVsReaction(t *testing.T) {
	m := rowMetrics()
	l := Layout(Entry{Name: "A", Mention: true}, 300, m)
	if len(l.Badges) != 1 || l.Badges[0].Kind != BadgeMention {
		t.Fatalf("mention row must carry BadgeMention: %+v", l.Badges)
	}
	l = Layout(Entry{Name: "A", Reaction: true}, 300, m)
	if len(l.Badges) != 1 || l.Badges[0].Kind != BadgeReaction {
		t.Fatalf("reaction row must carry BadgeReaction: %+v", l.Badges)
	}
	l = Layout(Entry{Name: "A", Mention: true, Reaction: true}, 300, m)
	if len(l.Badges) != 1 || l.Badges[0].Kind != BadgeMention {
		t.Fatalf("mention wins over reaction: %+v", l.Badges)
	}
	l = Layout(Entry{Name: "A", Poll: true, Reaction: true}, 300, m)
	if len(l.Badges) != 2 || l.Badges[0].Kind != BadgeReaction || l.Badges[1].Kind != BadgePoll {
		t.Fatalf("reaction then poll: %+v", l.Badges)
	}

	nl := Layout(Entry{Name: "A", Reaction: true}, 60, m)
	if len(nl.Badges) != 1 || nl.Badges[0].Kind != BadgeReaction {
		t.Fatalf("narrow reaction row must carry BadgeReaction: %+v", nl.Badges)
	}
}
