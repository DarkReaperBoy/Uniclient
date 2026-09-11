package cores

import (
	"fmt"

	"github.com/gotd/td/tg"
)

// Per-chat notification-sound surface (slice 121). Read-modify-write over
// account.getNotifySettings → account.updateNotifySettings so only the
// sound changes and the peer's mute/silent settings survive untouched —
// the same shape official clients use.

// notifySoundForKind maps a GUI kind onto the wire sound class.
func notifySoundForKind(kind string) (tg.NotificationSoundClass, error) {
	switch kind {
	case "default":
		return &tg.NotificationSoundDefault{}, nil
	case "none":
		return &tg.NotificationSoundNone{}, nil
	case "gentle":
		return &tg.NotificationSoundLocal{Title: "Gentle", Data: "uniclient-gentle"}, nil
	}
	return nil, fmt.Errorf("unknown sound kind: %s", kind)
}

// kindForNotifySound maps a wire sound class back to the GUI kind ("" when
// unset/unknown).
func kindForNotifySound(s tg.NotificationSoundClass) string {
	switch v := s.(type) {
	case *tg.NotificationSoundDefault:
		return "default"
	case *tg.NotificationSoundNone:
		return "none"
	case *tg.NotificationSoundLocal:
		if v.Title == "Gentle" || v.Data == "uniclient-gentle" {
			return "gentle"
		}
		return ""
	}
	return ""
}

// chatNotifySettings reads the current per-peer notify settings.
func (t *TelegramCore) chatNotifySettings(chatID string) (*tg.PeerNotifySettings, tg.InputPeerClass, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, nil, err
	}
	defer unlock()
	s, err := t.api.AccountGetNotifySettings(t.ctx, &tg.InputNotifyPeer{Peer: inputPeer})
	if err != nil {
		return nil, nil, err
	}
	return s, inputPeer, nil
}

// GetChatNotifySound returns the chat's sound override kind ("" = unset).
func (t *TelegramCore) GetChatNotifySound(chatID string) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return "", ErrAuth
	}
	s, _, err := t.chatNotifySettings(chatID)
	if err != nil {
		return "", err
	}
	if snd, ok := s.GetOtherSound(); ok {
		return kindForNotifySound(snd), nil
	}
	return "", nil
}

// SetChatNotifySound overrides the chat's notification sound. Mute/silent
// settings are preserved from the live state.
func (t *TelegramCore) SetChatNotifySound(chatID, kind string) error {
	snd, err := notifySoundForKind(kind)
	if err != nil {
		return err
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	s, inputPeer, err := t.chatNotifySettings(chatID)
	if err != nil {
		return err
	}
	settings := tg.InputPeerNotifySettings{}
	if s.Silent {
		settings.SetSilent(true)
	}
	if s.MuteUntil != 0 {
		settings.SetMuteUntil(s.MuteUntil)
	}
	settings.SetSound(snd)
	_, err = t.api.AccountUpdateNotifySettings(t.ctx, &tg.AccountUpdateNotifySettingsRequest{
		Peer:     &tg.InputNotifyPeer{Peer: inputPeer},
		Settings: settings,
	})
	return err
}
