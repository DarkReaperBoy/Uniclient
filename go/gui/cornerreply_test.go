package gui

import (
	"testing"

	"uniclient/engine"
	"uniclient/utils"
)

func mkCornerMsg(id string, out bool) engine.CachedMessage {
	return engine.CachedMessage{MsgID: id, IsOutgoing: out}
}

func TestEffectiveCornerReply(t *testing.T) {
	// tdesktop default: the corner reply button is ON.
	if !effectiveCornerReply(nil) {
		t.Error("nil config: corner reply should default ON (tdesktop)")
	}
	on, off := true, false
	if !effectiveCornerReply(&on) {
		t.Error("explicit on: should be ON")
	}
	if effectiveCornerReply(&off) {
		t.Error("explicit off: should be OFF")
	}
}

func TestFastReplyGate(t *testing.T) {
	cases := []struct {
		name     string
		cornerOn bool
		selOn    bool
		canReply bool
		m        engine.CachedMessage
		want     bool
	}{
		{"incoming hoverable", true, false, true, mkCornerMsg("1", false), true},
		{"own message excluded", true, false, true, mkCornerMsg("1", true), false},
		{"setting off", false, false, true, mkCornerMsg("1", false), false},
		{"selection mode hides", true, true, true, mkCornerMsg("1", false), false},
		{"read-only chat hides", true, false, false, mkCornerMsg("1", false), false},
		{"service message hidden", true, false, true, engine.CachedMessage{MsgID: "1", IsService: true}, false},
	}
	for _, tc := range cases {
		if got := fastReplyGate(tc.cornerOn, tc.selOn, tc.canReply, tc.m); got != tc.want {
			t.Errorf("%s: fastReplyGate = %v, want %v", tc.name, got, tc.want)
		}
	}
}

func TestConfigFieldChangesCornerReply(t *testing.T) {
	c := configFieldChanges("corner_reply", true)
	if c == nil || c.CornerReply == nil || !*c.CornerReply {
		t.Fatal("corner_reply(true): missing change")
	}
	c = configFieldChanges("corner_reply", false)
	if c == nil || c.CornerReply == nil || *c.CornerReply {
		t.Fatal("corner_reply(false): missing change")
	}
	_ = utils.AppConfig{}
}
