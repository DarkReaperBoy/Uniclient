package engine

import (
	"fmt"
	"sync"
	"time"

	"uniclient/cores"
)

type giftCache struct {
	mu     sync.Mutex
	byAcct map[string]GiftCacheEntry
}

type GiftCacheEntry struct {
	Gifts   *cores.StarGiftsResult
	fetched time.Time
}

var Gifts = giftCache{byAcct: map[string]GiftCacheEntry{}}

const giftCacheTTL = 10 * time.Minute

type StarsGiftOptionsFetcher interface {
	GetStarsGiftOptions(userID string) ([]cores.StarsGiftAmount, error)
}

type StarsBalanceFetcher interface {
	GetStarsBalance() (int64, error)
}

func (e *Engine) CachedStarGifts(accountID string) (*cores.StarGiftsResult, error) {
	Gifts.mu.Lock()
	if ent, ok := Gifts.byAcct[accountID]; ok && time.Since(ent.fetched) < giftCacheTTL {
		out := ent.Gifts
		Gifts.mu.Unlock()
		return out, nil
	}
	Gifts.mu.Unlock()

	fresh, err := e.GetStarGifts(accountID)
	if err != nil {
		return nil, err
	}
	Gifts.mu.Lock()
	Gifts.byAcct[accountID] = GiftCacheEntry{Gifts: fresh, fetched: time.Now()}
	Gifts.mu.Unlock()
	return fresh, nil
}

func (e *Engine) GetStarsGiftOptions(accountID, userID string) ([]cores.StarsGiftAmount, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StarsGiftOptionsFetcher)
	if !ok {
		return nil, fmt.Errorf("%w: stars gift options", cores.ErrNotSupported)
	}
	return fetcher.GetStarsGiftOptions(userID)
}

func (e *Engine) GiftStarsBalance(accountID string) (int64, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return 0, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return 0, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StarsBalanceFetcher)
	if !ok {
		return 0, fmt.Errorf("%w: stars balance", cores.ErrNotSupported)
	}
	return fetcher.GetStarsBalance()
}
