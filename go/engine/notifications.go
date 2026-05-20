package engine

import (
	"encoding/json"
	"fmt"
)

type contactSignUpNotifier interface {
	AccountGetContactSignUpNotification() (bool, error)
	AccountSetContactSignUpNotification(silent bool) (bool, error)
}

type callsDisabledToggler interface {
	ToggleCallsDisabledHere(disabled bool) error
}

type callsDisabledGetter interface {
	GetCallsDisabledHere() (bool, error)
}

type peerNotifyResetter interface {
	ResetPeerNotifySettings(chatID string) error
}

type defaultNotifySettingsUpdater interface {
	UpdateDefaultNotifySettings(peerType string, enabled bool, silent *bool) error
}

type defaultNotifyTimedMuter interface {
	MuteDefaultNotifyForDuration(peerType string, seconds int) error
}

type defaultNotifySettingsGetter interface {
	GetDefaultNotifySettings(peerType string) (map[string]interface{}, error)
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

func (e *Engine) GetCallsDisabledHere(accountID string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(callsDisabledGetter)
	if !ok {
		return false, nil
	}
	return g.GetCallsDisabledHere()
}

func (e *Engine) ResetPeerNotifySettings(accountID, chatID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	r, ok := acc.Core.(peerNotifyResetter)
	if !ok {
		return fmt.Errorf("core does not support resetting peer notify settings")
	}
	return r.ResetPeerNotifySettings(chatID)
}

func (e *Engine) GetLocalNotifyConfig(accountID string) (map[string]interface{}, error) {
	e.mu.Lock()
	defer e.mu.Unlock()

	prefix := "notify_config:" + accountID + ":"
	rows, err := e.db.Query(
		"SELECT key, value FROM kv WHERE key LIKE ?",
		prefix+"%",
	)
	if err != nil {
		// Fall back to legacy single-key format
		var val string
		err2 := e.db.QueryRow(
			"SELECT value FROM kv WHERE key = ?",
			"notify_config:"+accountID,
		).Scan(&val)
		if err2 != nil {
			return map[string]interface{}{}, nil
		}
		var config map[string]interface{}
		if err3 := json.Unmarshal([]byte(val), &config); err3 != nil {
			return map[string]interface{}{}, nil
		}
		return config, nil
	}
	defer rows.Close()

	result := map[string]interface{}{}
	for rows.Next() {
		var key, val string
		if err := rows.Scan(&key, &val); err != nil {
			continue
		}
		var entry map[string]interface{}
		if err := json.Unmarshal([]byte(val), &entry); err != nil {
			continue
		}
		configType, _ := entry["type"].(string)
		if configType == "" {
			continue
		}
		switch configType {
		case "pinned_messages":
			if enabled, ok := entry["enabled"].(bool); ok {
				result["pinned_messages"] = enabled
			}
		case "global_volume":
			if vol, ok := entry["volume"].(float64); ok {
				result["global_volume"] = int(vol)
			}
		case "per_type_volume":
			if vol, ok := entry["volume"].(float64); ok {
				peerType, _ := entry["peer_type"].(string)
				if peerType != "" {
					result["volume_"+peerType] = int(vol)
				}
			}
		case "sound_enabled":
			if enabled, ok := entry["enabled"].(bool); ok {
				result["sound_enabled"] = enabled
			}
		case "flash_bounce_enabled":
			if enabled, ok := entry["enabled"].(bool); ok {
				result["flash_bounce_enabled"] = enabled
			}
		}
	}
	return result, nil
}

func (e *Engine) UpdateDefaultNotifySettings(accountID, peerType string, enabled bool, silent *bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	u, ok := acc.Core.(defaultNotifySettingsUpdater)
	if !ok {
		return fmt.Errorf("core does not support default notify settings")
	}
	return u.UpdateDefaultNotifySettings(peerType, enabled, silent)
}

func (e *Engine) MuteDefaultNotifyForDuration(accountID, peerType string, seconds int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	m, ok := acc.Core.(defaultNotifyTimedMuter)
	if !ok {
		return fmt.Errorf("core does not support timed default mute")
	}
	return m.MuteDefaultNotifyForDuration(peerType, seconds)
}

func (e *Engine) GetDefaultNotifySettings(accountID, peerType string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(defaultNotifySettingsGetter)
	if !ok {
		return map[string]interface{}{
			"enabled":       true,
			"sound_enabled": true,
		}, nil
	}
	return g.GetDefaultNotifySettings(peerType)
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

type ringtoneUploader interface {
	UploadRingtone(fileName, mimeType string, data []byte) (map[string]interface{}, error)
}

type ringtoneDeleter interface {
	DeleteRingtone(documentID int64) error
}

type notificationExceptionsGetter interface {
	GetNotificationExceptions(peerType string) ([]map[string]interface{}, error)
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

func (e *Engine) UploadRingtone(accountID, fileName, mimeType string, data []byte) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	u, ok := acc.Core.(ringtoneUploader)
	if !ok {
		return nil, fmt.Errorf("core does not support ringtone upload")
	}
	return u.UploadRingtone(fileName, mimeType, data)
}

func (e *Engine) DeleteRingtone(accountID string, documentID int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	d, ok := acc.Core.(ringtoneDeleter)
	if !ok {
		return fmt.Errorf("core does not support ringtone deletion")
	}
	return d.DeleteRingtone(documentID)
}

func (e *Engine) GetNotificationExceptions(accountID, peerType string) ([]map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(notificationExceptionsGetter)
	if !ok {
		return []map[string]interface{}{}, nil
	}
	return g.GetNotificationExceptions(peerType)
}

func (e *Engine) SaveLocalNotifyConfig(accountID string, config map[string]interface{}) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	configType, _ := config["type"].(string)
	if configType == "" {
		configType = "default"
	}
	key := "notify_config:" + accountID + ":" + configType

	configJSON, err := json.Marshal(config)
	if err != nil {
		return err
	}

	_, err = e.db.Exec(
		`INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?`,
		key, string(configJSON), string(configJSON),
	)
	return err
}

func (e *Engine) GetMutedChatsByType(accountID string) (map[string]int, error) {
	rows, err := e.db.Query(
		"SELECT type, COUNT(*) FROM chats WHERE account_id = ? AND is_muted = 1 AND type IN (1, 2, 3) GROUP BY type",
		accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := map[string]int{"private": 0, "group": 0, "channel": 0}
	for rows.Next() {
		var typeVal int
		var count int
		if err := rows.Scan(&typeVal, &count); err != nil {
			continue
		}
		switch typeVal {
		case ChatTypeDMVal:
			result["private"] = count
		case ChatTypeGroupVal:
			result["group"] = count
		case ChatTypeChanVal:
			result["channel"] = count
		}
	}
	return result, nil
}
