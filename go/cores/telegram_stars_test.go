package cores

import (
	"testing"

	"github.com/gotd/td/bin"
	"github.com/gotd/td/tg"
)

// wireStarsStatus builds a PaymentsStarsStatus with two transactions and
// name-resolvable peers.
func wireStarsStatus() *tg.PaymentsStarsStatus {
	return &tg.PaymentsStarsStatus{
		Balance: &tg.StarsAmount{Amount: 123_000_000_000}, // 123 stars
		History: []tg.StarsTransaction{
			{
				ID:     "txn1",
				Amount: &tg.StarsAmount{Amount: 25_000_000_000}, // +25
				Date:   1737000000,
				Peer: &tg.StarsTransactionPeer{
					Peer: &tg.PeerUser{UserID: 7},
				},
			},
			{
				ID:          "txn2",
				Amount:      &tg.StarsAmount{Amount: -50_000_000_000}, // −50
				Date:        1737003600,
				Title:       "Boost a channel",
				Description: "Boost @durov",
				Flags:       mustStarsTxnFlags(),
				Peer: &tg.StarsTransactionPeer{
					Peer: &tg.PeerChannel{ChannelID: 3},
				},
			},
		},
		Users: []tg.UserClass{
			&tg.User{ID: 7, FirstName: "Alice"},
		},
		Chats: []tg.ChatClass{
			&tg.Channel{ID: 3, Title: "Durov's Channel"},
		},
		NextOffset: "nxt",
	}
}

// TestStarsStatusFromWire: the wire payload maps onto the typed status —
// balance carries through in nanostars, transactions keep their signed
// amounts and resolve counterparty names from the users/chats lists.
func TestStarsStatusFromWire(t *testing.T) {
	out := starsStatusFromWire(wireStarsStatus())
	if out.BalanceNano != 123_000_000_000 {
		t.Fatalf("BalanceNano = %d", out.BalanceNano)
	}
	if len(out.Txns) != 2 {
		t.Fatalf("txns = %d, want 2", len(out.Txns))
	}
	if out.NextOffset != "nxt" {
		t.Fatalf("NextOffset = %q", out.NextOffset)
	}
	tx1 := out.Txns[0]
	if tx1.ID != "txn1" || tx1.NanoStars != 25_000_000_000 || tx1.Date != 1737000000 {
		t.Fatalf("tx1 = %+v", tx1)
	}
	if tx1.PeerTitle != "Alice" {
		t.Fatalf("tx1 PeerTitle = %q, want Alice (resolved from Users)", tx1.PeerTitle)
	}
	tx2 := out.Txns[1]
	if tx2.NanoStars != -50_000_000_000 {
		t.Fatalf("tx2 NanoStars = %d, want negative (spent)", tx2.NanoStars)
	}
	if tx2.PeerTitle != "Durov's Channel" {
		t.Fatalf("tx2 PeerTitle = %q, want Durov's Channel (resolved from Chats)", tx2.PeerTitle)
	}
	if tx2.Title != "Boost a channel" || tx2.Description != "Boost @durov" {
		t.Fatalf("tx2 = %+v", tx2)
	}
}

// TestStarsStatusFromWireEmpty: nil payload / empty history → zero value,
// no panic.
func TestStarsStatusFromWireEmpty(t *testing.T) {
	if out := starsStatusFromWire(nil); out.BalanceNano != 0 || len(out.Txns) != 0 {
		t.Fatalf("nil = %+v", out)
	}
	if out := starsStatusFromWire(&tg.PaymentsStarsStatus{}); out.BalanceNano != 0 || len(out.Txns) != 0 {
		t.Fatalf("empty = %+v", out)
	}
}

// TestStarsStatusFromWireFlags: the pending/failed/refund/gift flags and
// unknown peers degrade honestly.
func TestStarsStatusFromWireFlags(t *testing.T) {
	st := &tg.PaymentsStarsStatus{
		History: []tg.StarsTransaction{
			{
				ID:     "f1",
				Amount: &tg.StarsAmount{Amount: 100},
				Peer: &tg.StarsTransactionPeer{
					Peer: &tg.PeerUser{UserID: 999}, // not in Users — no name
				},
				Pending: true,
				Refund:  true,
				Gift:    true,
			},
		},
	}
	out := starsStatusFromWire(st)
	tx := out.Txns[0]
	if !tx.Pending || !tx.Refund || !tx.Gift || tx.Failed {
		t.Fatalf("flags = %+v", tx)
	}
	if tx.PeerTitle != "" {
		t.Fatalf("unresolvable peer must yield empty title, got %q", tx.PeerTitle)
	}
	if tx.NanoStars != 100 {
		t.Fatalf("nanostars = %d, want raw carry-through", tx.NanoStars)
	}
}

// mustStarsTxnFlags sets the Title (bit 0) and Description (bit 1)
// conditional flags — the wire decoder does this; direct construction
// in tests must do it too.
func mustStarsTxnFlags() bin.Fields {
	var f bin.Fields
	f.Set(0) // Title
	f.Set(1) // Description
	return f
}
