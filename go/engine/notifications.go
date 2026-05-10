package engine

import "fmt"

type contactSignUpNotifier interface {
	AccountGetContactSignUpNotification() (bool, error)
	AccountSetContactSignUpNotification(silent bool) (bool, error)
}

type callsDisabledToggler interface {
	ToggleCallsDisabledHere(disabled bool) error
}

type defaultNotifySettingsUpdater interface {
	UpdateDefaultNotifySettings(peerType string, enabled bool) error
}

type reactionsNotifyGetter interface {
	GetReactionsNotifySettings() (map[string]interface{}, error)
}

type reactionsNotifySetter interface {
	SetReactionsNotifySettings(reactionsEnabled bool, reactionsFrom string, pollVotesEnabled bool, pollVotesFrom string, showSenderName bool) error
}

func (e *Engine) GetContactSignUpNotification(accountID string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return true, fmt.Errorf("account not found: %s", accountID)
	}
	n, ok := acc.Core.(contactSignUpNotifier)
	if !ok {
		return true, nil
	}
	return n.AccountGetContactSignUpNotification()
}

func (e *Engine) SetContactSignUpNotification(accountID string, silent bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	n, ok := acc.Core.(contactSignUpNotifier)
	if !ok {
		return fmt.Errorf("core does not support contact sign-up notifications")
	}
	_, err := n.AccountSetContactSignUpNotification(silent)
	return err
}

func (e *Engine) SetCallsDisabledHere(accountID string, disabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	t, ok := acc.Core.(callsDisabledToggler)
	if !ok {
		return fmt.Errorf("core does not support toggling calls")
	}
	return t.ToggleCallsDisabledHere(disabled)
}

func (e *Engine) UpdateDefaultNotifySettings(accountID, peerType string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	u, ok := acc.Core.(defaultNotifySettingsUpdater)
	if !ok {
		return fmt.Errorf("core does not support default notify settings")
	}
	return u.UpdateDefaultNotifySettings(peerType, enabled)
}

func (e *Engine) GetReactionsNotifySettings(accountID string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(reactionsNotifyGetter)
	if !ok {
		return map[string]interface{}{
			"reactions_enabled": true,
			"reactions_from":    "everyone",
			"poll_votes_enabled": true,
			"poll_votes_from":   "everyone",
			"show_sender_name":  true,
		}, nil
	}
	return g.GetReactionsNotifySettings()
}

func (e *Engine) SetReactionsNotifySettings(accountID string, reactionsEnabled bool, reactionsFrom string, pollVotesEnabled bool, pollVotesFrom string, showSenderName bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	s, ok := acc.Core.(reactionsNotifySetter)
	if !ok {
		return fmt.Errorf("core does not support reactions notify settings")
	}
	return s.SetReactionsNotifySettings(reactionsEnabled, reactionsFrom, pollVotesEnabled, pollVotesFrom, showSenderName)
}

type ringtoneGetter interface {
	GetSavedRingtones() ([]map[string]interface{}, error)
}

func (e *Engine) GetSavedRingtones(accountID string) ([]map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(ringtoneGetter)
	if !ok {
		return []map[string]interface{}{}, nil
	}
	return g.GetSavedRingtones()
}

func (e *Engine) GetMutedChatsByType(accountID string) (map[string]int, error) {
	rows, err := e.db.Query(
		"SELECT chat_type, COUNT(*) FROM chats WHERE account_id = ? AND is_muted = 1 GROUP BY chat_type",
		accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := map[string]int{"private": 0, "group": 0, "channel": 0}
	for rows.Next() {
		var chatType string
		var count int
		if err := rows.Scan(&chatType, &count); err != nil {
			continue
		}
		result[chatType] = count
	}
	return result, nil
}
