package engine

import (
	"fmt"
	"sync"
	"time"

	"uniclient/cores"
)

type giftCache struct {
	mu     sync.Mutex
	byAcct map[string]giftCacheEntry
}

type giftCacheEntry struct {
	gifts   *cores.StarGiftsResult
	fetched time.Time
}

var gifts = giftCache{byAcct: map[string]giftCacheEntry{}}

const giftCacheTTL = 10 * time.Minute

type StarsGiftOptionsFetcher interface {
	GetStarsGiftOptions(userID string) ([]cores.StarsGiftAmount, error)
}

type StarsBalanceFetcher interface {
	GetStarsBalance() (int64, error)
}

func (e *Engine) CachedStarGifts(accountID string) (*cores.StarGiftsResult, error) {
	gifts.mu.Lock()
	if ent, ok := gifts.byAcct[accountID]; ok && time.Since(ent.fetched) < giftCacheTTL {
		out := ent.gifts
		gifts.mu.Unlock()
		return out, nil
	}
	gifts.mu.Unlock()

	fresh, err := e.GetStarGifts(accountID)
	if err != nil {
		return nil, err
	}
	gifts.mu.Lock()
	gifts.byAcct[accountID] = giftCacheEntry{gifts: fresh, fetched: time.Now()}
	gifts.mu.Unlock()
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
