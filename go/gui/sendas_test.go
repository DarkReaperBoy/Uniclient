package gui

import (
	"testing"

	"uniclient/engine"
)

func saPeers(n int) []engine.SendAsPeerInfo {
	peers := []engine.SendAsPeerInfo{
		{PeerID: "10", DisplayName: "Me", IsChannel: false},
	}
	for i := 1; i < n; i++ {
		peers = append(peers, engine.SendAsPeerInfo{
			PeerID:      itoa64(int64(100 + i)),
			DisplayName: "Channel " + itoa(i),
			IsChannel:   true,
		})
	}
	return peers
}

func TestSendAsVisible(t *testing.T) {
	if sendAsRowVisible(saPeers(1)) {
		t.Fatal("single-identity chat shows the send-as row")
	}
	if !sendAsRowVisible(saPeers(2)) {
		t.Fatal("multi-identity chat hides the send-as row")
	}
	if sendAsRowVisible(nil) {
		t.Fatal("no identities must hide the row")
	}
}

func TestSendAsCurrent(t *testing.T) {
	peers := saPeers(3)
	if got := sendAsCurrent(peers, ""); got != "10" {
		t.Fatalf("default current = %q", got)
	}
	if got := sendAsCurrent(peers, "101"); got != "101" {
		t.Fatalf("saved current = %q", got)
	}
	if got := sendAsCurrent(peers, "999"); got != "10" {
		t.Fatalf("stale current = %q", got)
	}
}

func TestSendAsRowLabel(t *testing.T) {
	peers := saPeers(2)
	cur := sendAsCurrent(peers, "101")
	name, ok := sendAsName(peers, cur)
	if !ok || name != "Channel 1" {
		t.Fatalf("name = %q ok=%v", name, ok)
	}
	if _, ok := sendAsName(peers, "10"); !ok {
		t.Fatal("self peer not found")
	}
	if _, ok := sendAsName(peers, "424242"); ok {
		t.Fatal("unknown peer must not resolve")
	}
}

func TestSendAsPickerOrder(t *testing.T) {
	peers := saPeers(4)
	if len(peers) != 4 {
		t.Fatalf("peers = %d", len(peers))
	}
	if peers[0].IsChannel {
		t.Fatal("self must be first")
	}
	for _, p := range peers[1:] {
		if !p.IsChannel {
			t.Fatal("non-self entries expected to be channels")
		}
	}
}
