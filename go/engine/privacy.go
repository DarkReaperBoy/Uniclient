package engine

import (
	"fmt"
)

var PrivacyScopeKeys = []string{
	"last_seen",
	"phone_number",
	"profile_photo",
	"calls",
	"p2p",
	"forwards",
	"group_invites",
	"voice_messages",
	"about",
	"birthday",
}

func PrivacyScopeCloseFriends(key string) bool {
	switch key {
	case "last_seen", "profile_photo", "calls", "forwards",
		"group_invites", "voice_messages", "birthday":
		return true
	}
	return false
}

func ValidPrivacyScope(scope string) bool {
	switch scope {
	case "everybody", "contacts", "close_friends", "nobody":
		return true
	}
	return false
}

type privacyScopeGetter interface {
	GetPrivacyScope(key string) (string, error)
}

type privacyScopeSetter interface {
	SetPrivacyScope(key, scope string) error
}

func (e *Engine) GetPrivacyScopes(accountID string) (map[string]string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	g, ok := acc.Core.(privacyScopeGetter)
	if !ok {
		return nil, fmt.Errorf("core does not support privacy scopes")
	}
	scopes := make(map[string]string, len(PrivacyScopeKeys))
	for _, key := range PrivacyScopeKeys {
		scope, err := g.GetPrivacyScope(key)
		if err != nil {
			continue
		}
		scopes[key] = scope
	}
	return scopes, nil
}

func (e *Engine) SetPrivacyScope(accountID, key, scope string) error {
	if !ValidPrivacyScope(scope) {
		return fmt.Errorf("invalid privacy scope: %s", scope)
	}
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	s, ok := acc.Core.(privacyScopeSetter)
	if !ok {
		return fmt.Errorf("core does not support privacy scopes")
	}
	return s.SetPrivacyScope(key, scope)
}
