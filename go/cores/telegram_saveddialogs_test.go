package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

// Saved Messages sublists (slice 197): the pure half — the official
// saved_peer_id backfill pseudocode (core.telegram.org/api/saved-messages,
// for messages the server still sends without the layer-170+ field),
// pinned against constructed wire objects.

func TestDeriveSavedPeerID(t *testing.T) {
	const selfID = int64(11111111)
	// Wire field present → wins.
	m := &tg.Message{}
	m.PeerID = &tg.PeerUser{UserID: selfID}
	m.SetSavedPeerID(&tg.PeerChannel{ChannelID: 42})
	if got := deriveSavedPeerID(m, selfID); got != "-1000000000042" {
		t.Errorf("wire field: %q, want -1000000000042", got)
	}
	// Not a self-chat message (monoforum case) → not ours to derive.
	m = &tg.Message{}
	m.PeerID = &tg.PeerChannel{ChannelID: 7}
	if got := deriveSavedPeerID(m, selfID); got != "" {
		t.Errorf("non-self peer: %q, want empty", got)
	}
	// Self chat + fwd saved_from_peer → that peer.
	m = &tg.Message{}
	m.PeerID = &tg.PeerUser{UserID: selfID}
	fwd := &tg.MessageFwdHeader{}
	fwd.SetSavedFromPeer(&tg.PeerChannel{ChannelID: 99})
	m.SetFwdFrom(*fwd)
	if got := deriveSavedPeerID(m, selfID); got != "-1000000000099" {
		t.Errorf("fwd saved_from_peer: %q, want -1000000000099", got)
	}
	// Self chat + fwd from_id → ourselves (the sender's dialog).
	m = &tg.Message{}
	m.PeerID = &tg.PeerUser{UserID: selfID}
	fwd = &tg.MessageFwdHeader{}
	fwd.SetFromID(&tg.PeerUser{UserID: 133333333})
	m.SetFwdFrom(*fwd)
	if got := deriveSavedPeerID(m, selfID); got != "11111111" {
		t.Errorf("fwd from_id: %q, want self id", got)
	}
	// Self chat + fwd from_name only (forward-privacy) → the special
	// anonymous saved user 2666000.
	m = &tg.Message{}
	m.PeerID = &tg.PeerUser{UserID: selfID}
	fwd = &tg.MessageFwdHeader{}
	fwd.SetFromName("Hidden")
	m.SetFwdFrom(*fwd)
	if got := deriveSavedPeerID(m, selfID); got != "2666000" {
		t.Errorf("fwd from_name: %q, want 2666000", got)
	}
	// Self chat, plain message (no fwd header) → ourselves.
	m = &tg.Message{}
	m.PeerID = &tg.PeerUser{UserID: selfID}
	if got := deriveSavedPeerID(m, selfID); got != "11111111" {
		t.Errorf("plain self message: %q, want self id", got)
	}
}
