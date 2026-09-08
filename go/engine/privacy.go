package engine

import (
	"fmt"
)

// Privacy scopes (AyuGram parity): the settings-style keys mirror AyuGram's
// privacy rows; scopes are the simple four-value vocabulary the core
// translates to/from Telegram privacy rules.

// PrivacyScopeKeys is the ordered settings-style privacy key list shown on
// the Privacy & Security page.
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

// PrivacyScopeCloseFriends reports whether a key offers the "close friends"
// scope (mirrors which Telegram rows show that option).
func PrivacyScopeCloseFriends(key string) bool {
	switch key {
	case "last_seen", "profile_photo", "calls", "forwards",
		"group_invites", "voice_messages", "birthday":
		return true
	}
	return false
}

// ValidPrivacyScope reports whether scope is one of the four known values.
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

// GetPrivacyScopes reads the current privacy scope per key for one account.
// Keys the core cannot serve are reported with an empty scope string, so a
// partial failure still renders the rest of the page.
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

// SetPrivacyScope applies a privacy scope for one key on one account.
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
