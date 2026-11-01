package tests

import (
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/tg"
)

func TestNotifySoundOn(t *testing.T) {
	if !NotifySoundOn(nil) {
		t.Error("unset sound = default = on")
	}
	if !NotifySoundOn(&tg.NotificationSoundDefault{}) {
		t.Error("explicit default sound = on")
	}
	if NotifySoundOn(&tg.NotificationSoundNone{}) {
		t.Error("none sound = off")
	}
	if !NotifySoundOn(&tg.NotificationSoundLocal{Title: "chime"}) {
		t.Error("local sound = on")
	}
}

func TestNotifyPreviewsOf(t *testing.T) {
	var unset tg.PeerNotifySettings
	if !NotifyPreviewsOf(&unset) {
		t.Error("unset previews = default = shown")
	}
	shown := tg.PeerNotifySettings{}
	shown.SetShowPreviews(true)
	if !NotifyPreviewsOf(&shown) {
		t.Error("explicit true previews = shown")
	}
	hidden := tg.PeerNotifySettings{}
	hidden.SetShowPreviews(false)
	if NotifyPreviewsOf(&hidden) {
		t.Error("explicit false previews = hidden")
	}
}

func TestNotifySettingsInput(t *testing.T) {
	in := NotifySettingsInput(1700000000, nil, nil)
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
	in = NotifySettingsInput(0, &on, &off)
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

	in = NotifySettingsInput(0, &off, nil)
	snd, _ = in.GetSound()
	if _, is := snd.(*tg.NotificationSoundNone); !is {
		t.Errorf("sound off = %T, want NotificationSoundNone", snd)
	}
}

func TestChatNotifySettingsFromWire(t *testing.T) {
	s := tg.PeerNotifySettings{}
	s.SetMuteUntil(1750000000)
	s.SetOtherSound(&tg.NotificationSoundNone{})
	s.SetShowPreviews(false)
	got := ChatNotifySettingsFromWire(&s)
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
