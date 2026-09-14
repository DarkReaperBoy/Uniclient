package engine

// gifts.go — slice 211: star gifts. Optional-core surface over the
// telegram gift catalog / balance / purchase RPCs, with a per-account
// in-memory catalog cache (the catalog is effectively static between
// releases; the dialog re-reads the cache instantly and the send path
// never depends on it).

import (
	"fmt"
	"sync"
	"time"

	"uniclient/cores"
)

// GiftCore is the optional star-gift surface (slice 211).
type GiftCore interface {
	GetStarGifts() ([]cores.StarGiftInfo, error)
	GetStarsBalance() (int64, error)
	SendStarGift(chatID string, giftID int64, message string, hideName bool) error
}

// giftCache holds the per-account catalog with its fetch time.
type giftCache struct {
	mu     sync.Mutex
	byAcct map[string]giftCacheEntry
}

type giftCacheEntry struct {
	gifts   []cores.StarGiftInfo
	fetched time.Time
}

var gifts = giftCache{byAcct: map[string]giftCacheEntry{}}

// giftCacheTTL bounds how long a catalog read is served from memory.
const giftCacheTTL = 10 * time.Minute

// StarGiftsSupported reports whether the account's core exposes gifts.
func (e *Engine) StarGiftsSupported(accountID string) bool {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false
	}
	_, ok = acc.Core.(GiftCore)
	return ok
}

// giftCore resolves the gift surface for an account.
func (e *Engine) giftCore(accountID string) (GiftCore, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	gc, ok := acc.Core.(GiftCore)
	if !ok {
		return nil, fmt.Errorf("%w: star gifts", cores.ErrNotSupported)
	}
	return gc, nil
}

// GetStarGifts returns the purchasable gift catalog (cached briefly).
func (e *Engine) GetStarGifts(accountID string) ([]cores.StarGiftInfo, error) {
	gc, err := e.giftCore(accountID)
	if err != nil {
		return nil, err
	}
	gifts.mu.Lock()
	if ent, ok := gifts.byAcct[accountID]; ok && time.Since(ent.fetched) < giftCacheTTL {
		out := ent.gifts
		gifts.mu.Unlock()
		return out, nil
	}
	gifts.mu.Unlock()

	fresh, err := gc.GetStarGifts()
	if err != nil {
		return nil, err
	}
	gifts.mu.Lock()
	gifts.byAcct[accountID] = giftCacheEntry{gifts: fresh, fetched: time.Now()}
	gifts.mu.Unlock()
	return fresh, nil
}

// GetStarsBalance returns the account's star balance in nanostars.
func (e *Engine) GetStarsBalance(accountID string) (int64, error) {
	gc, err := e.giftCore(accountID)
	if err != nil {
		return 0, err
	}
	return gc.GetStarsBalance()
}

// SendStarGift purchases one gift for chatID from the account's balance.
func (e *Engine) SendStarGift(accountID, chatID string, giftID int64, message string, hideName bool) error {
	gc, err := e.giftCore(accountID)
	if err != nil {
		return err
	}
	return gc.SendStarGift(chatID, giftID, message, hideName)
}
