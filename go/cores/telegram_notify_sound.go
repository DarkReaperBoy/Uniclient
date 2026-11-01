package cores

import (
	"fmt"

	"github.com/gotd/td/tg"
)

func NotifySoundForKind(kind string) (tg.NotificationSoundClass, error) {
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

func KindForNotifySound(s tg.NotificationSoundClass) string {
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
		return KindForNotifySound(snd), nil
	}
	return "", nil
}

func (t *TelegramCore) SetChatNotifySound(chatID, kind string) error {
	snd, err := NotifySoundForKind(kind)
	if err != nil {
		return err
	}
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
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
	_, err = api.AccountUpdateNotifySettings(ctx, &tg.AccountUpdateNotifySettingsRequest{
		Peer:     &tg.InputNotifyPeer{Peer: inputPeer},
		Settings: settings,
	})
	return err
}
