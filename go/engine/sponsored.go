package engine

import (
	"fmt"
	"strings"
	"time"

	"uniclient/cores"
)

// Sponsored messages (Telegram channels + bots, slice 163): the engine
// layer over the core's sponsored surface — a 5-minute per-chat cache
// (tdesktop's SponsoredMessages::RequestCanAsk interval), one-shot
// view-reporting per cache window, and pass-through routing for the
// click / report / toggle RPCs.

// sponsoredTTL is how long a fetched sponsored block stays fresh
// (Telegram's documented 5-minute sponsored request interval).
const sponsoredTTL = 5 * time.Minute

type sponsoredCacheEntry struct {
	items        []cores.SponsoredMessageInfo
	postsBetween int
	fetchedAt    time.Time
	viewed       map[string]bool // random IDs already view-reported in this window
}

type SponsoredMessagesGetter interface {
	GetSponsoredMessages(chatID string) ([]cores.SponsoredMessageInfo, int, error)
	ViewSponsoredMessage(randomID string) error
	ClickSponsoredMessage(randomID string, media, fullscreen bool) error
	ReportSponsoredMessage(randomID, option string) (string, []cores.SponsoredReportOption, error)
	ToggleSponsoredMessages(enabled bool) error
}

// GetSponsoredMessages returns the sponsored messages for a channel or
// bot chat, served from the 5-minute cache when fresh. The cache key is
// account+chat; entries refresh lazily on the next call after expiry.
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
		// Serve nothing on error — the GUI shows no block (honest empty),
		// never a stale one past its window.
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

// MarkSponsoredViewed reports that the ad's full text became visible
// (messages.viewSponsoredMessage), once per cache window per message —
// the wire contract only wants the report when the block is actually
// (re)shown to the user.
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
		return nil // already reported this window
	}
	ent.viewed[randomID] = true
	e.sponsoredMu.Unlock()
	return getter.ViewSponsoredMessage(randomID)
}

// ClickSponsoredMessage reports a click on a sponsored message (the
// button vs the media block vs a fullscreen video ad).
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

// ReportSponsoredMessage walks one step of the iterative ad-report flow:
// an empty option requests the option list; a chosen option submits it.
// The result is the next choose-option chain ("" title = done).
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

// ToggleSponsoredMessages turns account-wide sponsored messages off/on
// (account.toggleSponsoredMessages — the Premium "No ads" lever; it is
// a setter, not a flip, so calls are idempotent).
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

// invalidateSponsoredCache drops the cached sponsored blocks (e.g. when
// the account disconnects). Cache-keyed, not content-keyed: harmless to
// call speculatively.
func (e *Engine) invalidateSponsoredCache(accountID string) {
	e.sponsoredMu.Lock()
	prefix := accountID + "|"
	for k := range e.sponsoredCache {
		if strings.HasPrefix(k, prefix) {
			delete(e.sponsoredCache, k)
		}
	}
	e.sponsoredMu.Unlock()
}
