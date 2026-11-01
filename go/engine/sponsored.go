package engine

import (
	"fmt"
	"time"

	"uniclient/cores"
)

const sponsoredTTL = 5 * time.Minute

type sponsoredCacheEntry struct {
	items        []cores.SponsoredMessageInfo
	postsBetween int
	fetchedAt    time.Time
	viewed       map[string]bool
}

type SponsoredMessagesGetter interface {
	GetSponsoredMessages(chatID string) ([]cores.SponsoredMessageInfo, int, error)
	ViewSponsoredMessage(randomID string) error
	ClickSponsoredMessage(randomID string, media, fullscreen bool) error
	ReportSponsoredMessage(randomID, option string) (string, []cores.SponsoredReportOption, error)
	ToggleSponsoredMessages(enabled bool) error
}

func (e *Engine) GetSponsoredMessages(accountID, chatID string) ([]cores.SponsoredMessageInfo, int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, 0, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, 0, fmt.Errorf("account not connected: %s", accountID)
	}
	getter, ok := acc.Core.(SponsoredMessagesGetter)
	if !ok {
		return nil, 0, fmt.Errorf("platform does not support sponsored messages")
	}

	key := accountID + "|" + chatID
	now := time.Now()

	e.sponsoredMu.Lock()
	if ent := e.sponsoredCache[key]; ent != nil && now.Sub(ent.fetchedAt) < sponsoredTTL {
		items, posts := ent.items, ent.postsBetween
		e.sponsoredMu.Unlock()
		return items, posts, nil
	}
	e.sponsoredMu.Unlock()

	items, posts, err := getter.GetSponsoredMessages(chatID)
	if err != nil {
		return nil, 0, err
	}

	e.sponsoredMu.Lock()
	if e.sponsoredCache == nil {
		e.sponsoredCache = map[string]*sponsoredCacheEntry{}
	}
	e.sponsoredCache[key] = &sponsoredCacheEntry{
		items:        items,
		postsBetween: posts,
		fetchedAt:    now,
		viewed:       map[string]bool{},
	}
	e.sponsoredMu.Unlock()
	return items, posts, nil
}

func (e *Engine) MarkSponsoredViewed(accountID, chatID, randomID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	getter, ok := acc.Core.(SponsoredMessagesGetter)
	if !ok {
		return fmt.Errorf("platform does not support sponsored messages")
	}

	key := accountID + "|" + chatID
	e.sponsoredMu.Lock()
	ent := e.sponsoredCache[key]
	if ent == nil {
		e.sponsoredMu.Unlock()
		return fmt.Errorf("no sponsored cache for chat %s", chatID)
	}
	if ent.viewed[randomID] {
		e.sponsoredMu.Unlock()
		return nil
	}
	ent.viewed[randomID] = true
	e.sponsoredMu.Unlock()
	return getter.ViewSponsoredMessage(randomID)
}

func (e *Engine) ClickSponsoredMessage(accountID, randomID string, media, fullscreen bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	getter, ok := acc.Core.(SponsoredMessagesGetter)
	if !ok {
		return fmt.Errorf("platform does not support sponsored messages")
	}
	return getter.ClickSponsoredMessage(randomID, media, fullscreen)
}

func (e *Engine) ReportSponsoredMessage(accountID, randomID, option string) (string, []cores.SponsoredReportOption, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", nil, fmt.Errorf("account not connected: %s", accountID)
	}
	getter, ok := acc.Core.(SponsoredMessagesGetter)
	if !ok {
		return "", nil, fmt.Errorf("platform does not support sponsored messages")
	}
	return getter.ReportSponsoredMessage(randomID, option)
}

func (e *Engine) ToggleSponsoredMessages(accountID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	getter, ok := acc.Core.(SponsoredMessagesGetter)
	if !ok {
		return fmt.Errorf("platform does not support sponsored messages")
	}
	return getter.ToggleSponsoredMessages(enabled)
}
