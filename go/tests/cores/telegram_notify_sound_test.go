package tests

import (
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/tg"
)

func TestNotifySoundKindRoundTrip(t *testing.T) {
	for _, kind := range []string{"default", "none", "gentle"} {
		snd, err := NotifySoundForKind(kind)
		if err != nil {
			t.Fatalf("kind %q: %v", kind, err)
		}
		if back := KindForNotifySound(snd); back != kind {
			t.Errorf("round-trip %q → %q", kind, back)
		}
	}
	if _, err := NotifySoundForKind("bogus"); err == nil {
		t.Errorf("unknown kind must error")
	}
	if got := KindForNotifySound(nil); got != "" {
		t.Errorf("nil sound = %q, want \"\"", got)
	}
	if got := KindForNotifySound(&tg.NotificationSoundLocal{Title: "Other"}); got != "" {
		t.Errorf("foreign local sound = %q, want \"\"", got)
	}
}
