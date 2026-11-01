package tests

import (
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/bin"
	"github.com/gotd/td/tg"
)

func wireStarsStatus() *tg.PaymentsStarsStatus {
	return &tg.PaymentsStarsStatus{
		Balance: &tg.StarsAmount{Amount: 123_000_000_000},
		History: []tg.StarsTransaction{
			{
				ID:     "txn1",
				Amount: &tg.StarsAmount{Amount: 25_000_000_000},
				Date:   1737000000,
				Peer: &tg.StarsTransactionPeer{
					Peer: &tg.PeerUser{UserID: 7},
				},
			},
			{
				ID:          "txn2",
				Amount:      &tg.StarsAmount{Amount: -50_000_000_000},
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

func TestStarsStatusFromWire(t *testing.T) {
	out := StarsStatusFromWire(wireStarsStatus())
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

func TestStarsStatusFromWireEmpty(t *testing.T) {
	if out := StarsStatusFromWire(nil); out.BalanceNano != 0 || len(out.Txns) != 0 {
		t.Fatalf("nil = %+v", out)
	}
	if out := StarsStatusFromWire(&tg.PaymentsStarsStatus{}); out.BalanceNano != 0 || len(out.Txns) != 0 {
		t.Fatalf("empty = %+v", out)
	}
}

func TestStarsStatusFromWireFlags(t *testing.T) {
	st := &tg.PaymentsStarsStatus{
		History: []tg.StarsTransaction{
			{
				ID:     "f1",
				Amount: &tg.StarsAmount{Amount: 100},
				Peer: &tg.StarsTransactionPeer{
					Peer: &tg.PeerUser{UserID: 999},
				},
				Pending: true,
				Refund:  true,
				Gift:    true,
			},
		},
	}
	out := StarsStatusFromWire(st)
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

func mustStarsTxnFlags() bin.Fields {
	var f bin.Fields
	f.Set(0)
	f.Set(1)
	return f
}
