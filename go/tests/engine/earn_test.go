package tests

import (
	"errors"
	"testing"
	. "uniclient/engine"

	"uniclient/cores"
)

type withdrawStub struct {
	cores.StubCore
	url     string
	err     error
	calls   int
	lastTon bool
	lastAmt int64
	lastPw  string
}

func (s *withdrawStub) WithdrawStarsRevenue(chatID string, ton bool, amount int64, password string) (string, error) {
	s.calls++
	s.lastTon, s.lastAmt, s.lastPw = ton, amount, password
	return s.url, s.err
}

func newEarnEngine(t *testing.T, core cores.Core) *Engine {
	t.Helper()
	e := newTestEngine(t)
	if _, err := e.ForTestDb().Exec(
		`INSERT OR IGNORE INTO accounts (id, platform, display_name, sort_order, created_at)
                 VALUES ('tg', 'telegram', 'Test', 0, 0)`); err != nil {
		t.Fatal(err)
	}
	if err := e.AttachAccount("tg", "telegram", core); err != nil {
		t.Fatal(err)
	}
	return e
}

func TestWithdrawStarsRevenue(t *testing.T) {
	st := &withdrawStub{url: "https://fragment.com/withdraw/abc"}
	e := newEarnEngine(t, st)

	url, err := e.WithdrawStarsRevenue("tg", "-1001234", true, 0, "pw123")
	if err != nil {
		t.Fatal(err)
	}
	if url != st.url {
		t.Fatalf("url = %q", url)
	}
	if st.calls != 1 || !st.lastTon || st.lastPw != "pw123" {
		t.Fatalf("call = ton:%v pw:%q", st.lastTon, st.lastPw)
	}

	st.err = errors.New("boom")
	if _, err := e.WithdrawStarsRevenue("tg", "-1001234", true, 0, ""); err == nil {
		t.Error("core error must surface")
	}

	e2 := newEarnEngine(t, &plainStub{})
	if _, err := e2.WithdrawStarsRevenue("tg", "c", false, 1, ""); err == nil {
		t.Error("plain stub must not withdraw")
	}
	if _, err := e.WithdrawStarsRevenue("ghost", "c", false, 1, ""); err == nil {
		t.Error("unknown account must error")
	}
}
