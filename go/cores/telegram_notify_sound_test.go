package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

// notifySoundForKind / kindForNotifySound round-trip (slice 121).
func TestNotifySoundKindRoundTrip(t *testing.T) {
	for _, kind := range []string{"default", "none", "gentle"} {
		snd, err := notifySoundForKind(kind)
		if err != nil {
			t.Fatalf("kind %q: %v", kind, err)
		}
		if back := kindForNotifySound(snd); back != kind {
			t.Errorf("round-trip %q → %q", kind, back)
		}
	}
	if _, err := notifySoundForKind("bogus"); err == nil {
		t.Errorf("unknown kind must error")
	}
	if got := kindForNotifySound(nil); got != "" {
		t.Errorf("nil sound = %q, want \"\"", got)
	}
	if got := kindForNotifySound(&tg.NotificationSoundLocal{Title: "Other"}); got != "" {
		t.Errorf("foreign local sound = %q, want \"\"", got)
	}
}
