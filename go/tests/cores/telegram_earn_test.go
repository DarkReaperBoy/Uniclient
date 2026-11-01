package tests

import (
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/tg"
)

func TestWithdrawStarsRevenueRequest(t *testing.T) {
	peer := &tg.InputPeerChannel{ChannelID: 42, AccessHash: 7}
	empty := &tg.InputCheckPasswordEmpty{}

	req := WithdrawStarsRevenueRequest(peer, true, 0, empty)
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

	srp := &tg.InputCheckPasswordSRP{SRPID: 99}
	req2 := WithdrawStarsRevenueRequest(peer, false, 500_000_000_000, srp)
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
