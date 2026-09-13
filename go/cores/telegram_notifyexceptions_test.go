package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

// notifySoundOn (slice 174): a peer's notification sound state — the
// ternary OtherSound field. Unset (nil) = the global default = on;
// NotificationSoundNone = off; anything else (default/local/ringtone) = on.
func TestNotifySoundOn(t *testing.T) {
	if !notifySoundOn(nil) {
		t.Error("unset sound = default = on")
	}
	if !notifySoundOn(&tg.NotificationSoundDefault{}) {
		t.Error("explicit default sound = on")
	}
	if notifySoundOn(&tg.NotificationSoundNone{}) {
		t.Error("none sound = off")
	}
	if !notifySoundOn(&tg.NotificationSoundLocal{Title: "chime"}) {
		t.Error("local sound = on")
	}
}

// notifyPreviewsOf (slice 174): the ternary ShowPreviews — unset = default
// = shown; an explicit false hides.
func TestNotifyPreviewsOf(t *testing.T) {
	var unset tg.PeerNotifySettings
	if !notifyPreviewsOf(&unset) {
		t.Error("unset previews = default = shown")
	}
	shown := tg.PeerNotifySettings{}
	shown.SetShowPreviews(true)
	if !notifyPreviewsOf(&shown) {
		t.Error("explicit true previews = shown")
	}
	hidden := tg.PeerNotifySettings{}
	hidden.SetShowPreviews(false)
	if notifyPreviewsOf(&hidden) {
		t.Error("explicit false previews = hidden")
	}
}

// notifySettingsInput (slice 174): the write-side builder — mute_until
// always rides; sound and previews ride only when the caller provided a
// value (nil = leave to the server default), sound mapping true → default,
// false → none.
func TestNotifySettingsInput(t *testing.T) {
	in := notifySettingsInput(1700000000, nil, nil)
	if in.MuteUntil != 1700000000 {
		t.Errorf("mute_until = %d", in.MuteUntil)
	}
	if _, ok := in.GetSound(); ok {
		t.Error("nil sound: the flag must stay unset")
	}
	if _, ok := in.GetShowPreviews(); ok {
		t.Error("nil previews: the flag must stay unset")
	}

	on := true
	off := false
	in = notifySettingsInput(0, &on, &off)
	if in.MuteUntil != 0 {
		t.Errorf("unmute = %d, want 0", in.MuteUntil)
	}
	snd, ok := in.GetSound()
	if !ok {
		t.Fatal("sound provided: the flag must be set")
	}
	if _, is := snd.(*tg.NotificationSoundDefault); !is {
		t.Errorf("sound on = %T, want NotificationSoundDefault", snd)
	}
	pv, ok := in.GetShowPreviews()
	if !ok || pv {
		t.Errorf("previews off = (%v,%v)", pv, ok)
	}

	in = notifySettingsInput(0, &off, nil)
	snd, _ = in.GetSound()
	if _, is := snd.(*tg.NotificationSoundNone); !is {
		t.Errorf("sound off = %T, want NotificationSoundNone", snd)
	}
}

// ChatNotifySettings decode from the wire (slice 174).
func TestChatNotifySettingsFromWire(t *testing.T) {
	s := tg.PeerNotifySettings{}
	s.SetMuteUntil(1750000000)
	s.SetOtherSound(&tg.NotificationSoundNone{})
	s.SetShowPreviews(false)
	got := chatNotifySettingsFromWire(&s)
	if !got.Muted || got.MuteUntil != 1750000000 {
		t.Errorf("mute = (%v,%d)", got.Muted, got.MuteUntil)
	}
	if got.SoundOn {
		t.Error("otherSound none → SoundOn false")
	}
	if got.ShowPreviews {
		t.Error("explicit false previews")
	}
}
