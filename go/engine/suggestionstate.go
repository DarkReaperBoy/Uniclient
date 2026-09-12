package engine

// suggestionstate.go — slice 171: the engine-side aggregate for the
// chat-list top-bar suggestion card (tdesktop dialogs/suggestions).
//
// Data sources, per the tdesktop promo_suggestions component:
//   - help.getPromoData → pending suggestion KEYS + the optional custom
//     card (server-provided title/description/url);
//   - contacts.getBirthdays → contacts whose birthday is today (the
//     BIRTHDAY_CONTACTS_TODAY card is fully local data);
//   - the self user's photo/birthday state gates BIRTHDAY_SETUP and
//     USERPIC_SETUP.
//
// Dismissal: help.dismissSuggestion is async server-side; the engine
// keeps the local dismissal immediately so the card hides at once.

import (
	"fmt"
	"sync"
	"time"

	"uniclient/cores"
)

// PromoSuggestionInfo is one renderable suggestion card.
type PromoSuggestionInfo struct {
	Key         string `json:"key"`
	Title       string `json:"title"`
	Description string `json:"description"`
	URL         string `json:"url,omitempty"`
}

// BirthdayContactInfo is a contact with a birthday today.
type BirthdayContactInfo struct {
	UserID int64  `json:"user_id"`
	Name   string `json:"name"`
}

// SelfSuggestionStateInfo gates the setup suggestions.
type SelfSuggestionStateInfo struct {
	PhotoSet        bool `json:"photo_set"`
	BirthdaySet     bool `json:"birthday_set"`
	BirthdayIsToday bool `json:"birthday_is_today"`
}

// SuggestionState is the whole renderable suggestion surface for one
// account (what the GUI bar picks from).
type SuggestionState struct {
	Pending          []string                `json:"pending"`
	Custom           *PromoSuggestionInfo    `json:"custom,omitempty"`
	BirthdayContacts []BirthdayContactInfo   `json:"birthday_contacts,omitempty"`
	Self             SelfSuggestionStateInfo `json:"self"`
	Dismissed        map[string]bool         `json:"-"`
}

// suggestionDismiss tracks locally-dismissed keys per account (they stay
// hidden even while the server still lists them).
type suggestionDismiss struct {
	mu   sync.Mutex
	keys map[string]map[string]bool // accountID → key → dismissed
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

// GetSuggestionState assembles the suggestion surface for an account.
// Non-Telegram cores return an empty state (no suggestions to render).
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

// DismissSuggestion hides a suggestion: local immediately, server-side
// via help.dismissSuggestion (async, best-effort).
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
		_ = d.DismissSuggestion(key) // best-effort; the local hide stands
	}
	return nil
}

// SuggestionDismissed reports a locally-dismissed key.
func (e *Engine) SuggestionDismissed(accountID, key string) bool {
	return suggestionDismissed.has(accountID, key)
}

// suggestionTTL bounds refetches (tdesktop's kTopPromotionInterval is
// hourly; the GUI caches per account+day).
const suggestionTTL = time.Hour
