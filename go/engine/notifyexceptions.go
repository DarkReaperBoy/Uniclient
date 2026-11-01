package engine

import (
	"fmt"

	"uniclient/cores"
)

type ChatNotifySettingsGetter interface {
	GetChatNotifySettings(chatID string) (*cores.ChatNotifySettings, error)
}

func (e *Engine) GetChatNotifySettings(accountID, chatID string) (*cores.ChatNotifySettings, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	g, ok := acc.Core.(ChatNotifySettingsGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support notify exceptions")
	}
	return g.GetChatNotifySettings(chatID)
}

type ChatNotifySettingsSetter interface {
	SetChatNotifySettings(chatID string, muteUntil int32, soundOn, showPreviews *bool) error
}

func (e *Engine) SetChatNotifySettings(accountID, chatID string, muteUntil int32, soundOn, showPreviews *bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	s, ok := acc.Core.(ChatNotifySettingsSetter)
	if !ok {
		return fmt.Errorf("platform does not support notify exceptions")
	}
	if err := s.SetChatNotifySettings(chatID, muteUntil, soundOn, showPreviews); err != nil {
		return err
	}
	muted := muteUntil > 0
	flag := 0
	if muted {
		flag = 1
	}
	e.db.Exec(
		"UPDATE chats SET is_muted = ?, mute_until = ? WHERE account_id = ? AND chat_id = ?",
		flag, muteUntil, accountID, chatID,
	)
	e.emitChatUpdate(accountID, chatID)
	return nil
}
