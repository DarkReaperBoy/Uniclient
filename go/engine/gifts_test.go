package engine

// gifts_test.go — slice 211 tests: the gift catalog cache (cold fetch →
// warm read served from memory without a second core call) and the
// options/balance wrapper gates.

import (
	"testing"

	"uniclient/cores"
)

type giftStub struct {
	cores.StubCore
	catalog  *cores.StarGiftsResult
	fetches  int
	options  []cores.StarsGiftAmount
	optCalls []string
	balance  int64
}

func (s *giftStub) GetStarGifts() (*cores.StarGiftsResult, error) {
	s.fetches++
	return s.catalog, nil
}

func (s *giftStub) GetStarsGiftOptions(userID string) ([]cores.StarsGiftAmount, error) {
	s.optCalls = append(s.optCalls, userID)
	return s.options, nil
}

func (s *giftStub) GetStarsBalance() (int64, error) { return s.balance, nil }

func newGiftEngine(t *testing.T, core *giftStub) *Engine {
	t.Helper()
	e := newTestEngine(t)
	if _, err := e.db.Exec(
		`INSERT OR IGNORE INTO accounts (id, platform, display_name, sort_order, created_at)
                 VALUES ('tg', 'telegram', 'Test', 0, 0)`); err != nil {
		t.Fatal(err)
	}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: core}}
	return e
}

func TestCachedStarGifts(t *testing.T) {
	st := &giftStub{catalog: &cores.StarGiftsResult{Gifts: []cores.StarGiftItem{
		{ID: 5001, Stars: 50, ThumbB64: "AA"},
	}}}
	e := newGiftEngine(t, st)

	first, err := e.CachedStarGifts("tg")
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Gifts) != 1 || first.Gifts[0].ID != 5001 {
		t.Fatalf("cold catalog = %+v", first)
	}
	if st.fetches != 1 {
		t.Fatalf("fetches = %d, want 1", st.fetches)
	}

	// Warm read: no second core call.
	second, err := e.CachedStarGifts("tg")
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Gifts) != 1 {
		t.Fatalf("warm catalog = %+v", second)
	}
	if st.fetches != 1 {
		t.Fatalf("warm read re-fetched: %d", st.fetches)
	}
}

func TestGiftOptionsAndBalance(t *testing.T) {
	st := &giftStub{
		options: []cores.StarsGiftAmount{{Stars: 100, Currency: "USD", Amount: 200}},
		balance: 5_000_000_000, // 5 stars in nanostars
	}
	e := newGiftEngine(t, st)

	opts, err := e.GetStarsGiftOptions("tg", "42")
	if err != nil {
		t.Fatal(err)
	}
	if len(opts) != 1 || opts[0].Stars != 100 {
		t.Fatalf("options = %+v", opts)
	}
	if len(st.optCalls) != 1 || st.optCalls[0] != "42" {
		t.Fatalf("option calls = %v", st.optCalls)
	}

	bal, err := e.GiftStarsBalance("tg")
	if err != nil {
		t.Fatal(err)
	}
	if bal != 5_000_000_000 {
		t.Fatalf("balance = %d", bal)
	}

	// Plain stubs lack the surface → honest errors.
	e2 := newGiftEngine(t, &plainStub{})
	if _, err := e2.GetStarsGiftOptions("tg", "1"); err == nil {
		t.Error("plain stub must not expose gift options")
	}
	if _, err := e2.GiftStarsBalance("tg"); err == nil {
		t.Error("plain stub must not expose the balance")
	}
}
