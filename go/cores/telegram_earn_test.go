package cores

// telegram_earn_test.go — slice 213 tests-first: the stars-revenue
// withdrawal request builder (ton vs amount flag mapping, SRP payload
// choice — tdesktop HandleWithdrawalButton semantics).

import (
	"testing"

	"github.com/gotd/td/tg"
)

func TestWithdrawStarsRevenueRequest(t *testing.T) {
	peer := &tg.InputPeerChannel{ChannelID: 42, AccessHash: 7}
	empty := &tg.InputCheckPasswordEmpty{}

	// TON mode: f_ton only, amount unset (channel revenue — full balance).
	req := withdrawStarsRevenueRequest(peer, true, 0, empty)
	if !req.Ton {
		t.Error("ton flag missing")
	}
	if req.Amount != 0 {
		t.Errorf("ton mode carries an amount: %d", req.Amount)
	}
	if ch, ok := req.Peer.(*tg.InputPeerChannel); !ok || ch.ChannelID != 42 {
		t.Errorf("peer = %T", req.Peer)
	}
	if _, isEmpty := req.Password.(*tg.InputCheckPasswordEmpty); !isEmpty {
		t.Errorf("password = %T, want empty check", req.Password)
	}

	// Stars mode: f_amount (nanostars), no ton flag.
	srp := &tg.InputCheckPasswordSRP{SRPID: 99}
	req2 := withdrawStarsRevenueRequest(peer, false, 500_000_000_000, srp)
	if req2.Ton {
		t.Error("stars mode must not carry the ton flag")
	}
	if req2.Amount != 500_000_000_000 {
		t.Errorf("amount = %d", req2.Amount)
	}
	if s, ok := req2.Password.(*tg.InputCheckPasswordSRP); !ok || s.SRPID != 99 {
		t.Errorf("password = %T, want the SRP payload", req2.Password)
	}
}
