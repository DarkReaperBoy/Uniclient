package engine

import (
	"fmt"

	"uniclient/cores"
)

// Per-chat notification exceptions (AyuGram parity slice 174, tdesktop
// notify exceptions): the mute picker grows sound + message-preview
// toggles backed by account.get/updateNotifySettings. The engine passes
// through to the core (Telegram); the mute cache itself keeps riding the
// existing MuteChat + updateNotifySettings push path.

// ChatNotifySettingsGetter reads a chat's notification exception state.
type ChatNotifySettingsGetter interface {
	GetChatNotifySettings(chatID string) (*cores.ChatNotifySettings, error)
}

// GetChatNotifySettings returns the chat's notification exception state
// (sound on / previews shown / muted), read live from the server.
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

// ChatNotifySettingsSetter writes a chat's notification exception:
// mute_until always rides; sound/previews only when non-nil.
type ChatNotifySettingsSetter interface {
	SetChatNotifySettings(chatID string, muteUntil int32, soundOn, showPreviews *bool) error
}

// SetChatNotifySettings writes the chat's notification exception and
// mirrors the mute into the cached chat row (the same optimistic update
// MuteChat performs; the server's updateNotifySettings push reconciles).
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
	// Optimistic mute mirror (slice 136 semantics): 0 = unmuted, past
	// dates clamp to now, int32-max stays forever (0 in our encoding).
	muted := muteUntil > 0
	flag := 0
	if muted {
		flag = 1
	}
	e.db.Exec(
		"UPDATE chats SET is_muted = ?, mute_until = ? WHERE account_id = ? AND chat_id = ?",
		flag, muteUntil, accountID, chatID,
	)
	e.emitChatUpdate(accountID, chatID) // same chat-row refresh MuteChat uses
	return nil
}
