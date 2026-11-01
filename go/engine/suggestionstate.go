package engine

import (
	"fmt"
	"sync"

	"uniclient/cores"
)

type PromoSuggestionInfo struct {
	Key         string `json:"key"`
	Title       string `json:"title"`
	Description string `json:"description"`
	URL         string `json:"url,omitempty"`
}

type BirthdayContactInfo struct {
	UserID int64  `json:"user_id"`
	Name   string `json:"name"`
}

type SelfSuggestionStateInfo struct {
	PhotoSet        bool `json:"photo_set"`
	BirthdaySet     bool `json:"birthday_set"`
	BirthdayIsToday bool `json:"birthday_is_today"`
}

type SuggestionState struct {
	Pending          []string                `json:"pending"`
	Custom           *PromoSuggestionInfo    `json:"custom,omitempty"`
	BirthdayContacts []BirthdayContactInfo   `json:"birthday_contacts,omitempty"`
	Self             SelfSuggestionStateInfo `json:"self"`
	Dismissed        map[string]bool         `json:"-"`
}

type suggestionDismiss struct {
	mu   sync.Mutex
	keys map[string]map[string]bool
}

var suggestionDismissed = &suggestionDismiss{keys: map[string]map[string]bool{}}

func (d *suggestionDismiss) has(accountID, key string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.keys[accountID][key]
}

func (d *suggestionDismiss) set(accountID, key string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.keys[accountID] == nil {
		d.keys[accountID] = map[string]bool{}
	}
	d.keys[accountID][key] = true
}

func (e *Engine) GetSuggestionState(accountID string) (*SuggestionState, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}

	type promoSuggestions interface {
		GetPromoSuggestions() (cores.PromoSuggestionsSnapshot, error)
	}
	type birthdayContacts interface {
		GetTodayBirthdayContacts() ([]cores.BirthdayContact, error)
	}
	type selfState interface {
		GetSelfSuggestionState() (cores.SelfSuggestionState, error)
	}

	st := &SuggestionState{}
	if ps, ok := acc.Core.(promoSuggestions); ok {
		if snap, err := ps.GetPromoSuggestions(); err == nil {
			st.Pending = snap.Pending
			if snap.Custom != nil {
				st.Custom = &PromoSuggestionInfo{
					Key:         snap.Custom.Key,
					Title:       snap.Custom.Title,
					Description: snap.Custom.Description,
					URL:         snap.Custom.URL,
				}
			}
		}
	}
	if bc, ok := acc.Core.(birthdayContacts); ok {
		if list, err := bc.GetTodayBirthdayContacts(); err == nil {
			for _, c := range list {
				st.BirthdayContacts = append(st.BirthdayContacts, BirthdayContactInfo{
					UserID: c.UserID,
					Name:   c.Name,
				})
			}
		}
	}
	if ss, ok := acc.Core.(selfState); ok {
		if self, err := ss.GetSelfSuggestionState(); err == nil {
			st.Self = SelfSuggestionStateInfo{
				PhotoSet:        self.PhotoSet,
				BirthdaySet:     self.BirthdaySet,
				BirthdayIsToday: self.BirthdayIsToday,
			}
		}
	}
	return st, nil
}

func (e *Engine) DismissSuggestion(accountID, key string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	suggestionDismissed.set(accountID, key)

	type dismisser interface {
		DismissSuggestion(key string) error
	}
	if d, ok := acc.Core.(dismisser); ok {
		_ = d.DismissSuggestion(key)
	}
	return nil
}

func (e *Engine) SuggestionDismissed(accountID, key string) bool {
	return suggestionDismissed.has(accountID, key)
}
