package gui

// 1:1 call overlay (AyuGram parity slice 101): header call-button gating,
// the call session state machine fed by engine call events, the status line
// (ringing/connecting/elapsed/ended), control visibility per state, and the
// post-end auto-dismiss window. Pure derivations locked here — the overlay
// itself only renders what these decide.

import (
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/engine"
)

func TestDMCallButtons(t *testing.T) {
	dm := engine.ChatInfo{Type: engine.ChatTypeDMVal, ChatID: "7"}
	calls := []string{cores.CapText, cores.CapCalls}
	if v, vid := dmCallButtons(dm, calls); !v || !vid {
		t.Fatalf("DM + CALLS cap: voice=%v video=%v, want true/true", v, vid)
	}
	// No CALLS capability → no buttons (honest gating, §1.10).
	if v, vid := dmCallButtons(dm, []string{cores.CapText}); v || vid {
		t.Fatalf("no CALLS cap: voice=%v video=%v, want false/false", v, vid)
	}
	// Bots cannot be called.
	bot := engine.ChatInfo{Type: engine.ChatTypeDMVal, IsBot: true}
	if v, vid := dmCallButtons(bot, calls); v || vid {
		t.Fatalf("bot DM: voice=%v video=%v, want false/false", v, vid)
	}
	// Groups/channels never get 1:1 call buttons (group calls have their own bar).
	group := engine.ChatInfo{Type: engine.ChatTypeGroupVal}
	if v, vid := dmCallButtons(group, calls); v || vid {
		t.Fatalf("group chat: voice=%v video=%v, want false/false", v, vid)
	}
}

func TestCallUIOutgoingInit(t *testing.T) {
	c := newOutgoingCall("acct", "7", "Alice", true, "call1")
	if c.accountID != "acct" || c.chatID != "7" || c.peerName != "Alice" {
		t.Fatalf("fields: %+v", c)
	}
	if !c.video || c.incoming {
		t.Fatalf("video=%v incoming=%v, want true/false", c.video, c.incoming)
	}
	if c.state != string(cores.CallStateRinging) || c.callID != "call1" {
		t.Fatalf("state=%q callID=%q, want ringing/call1", c.state, c.callID)
	}
}

func TestCallUIIncomingFromSession(t *testing.T) {
	cs := &cores.CallSession{
		ID:     "call2",
		ChatID: "8",
		State:  cores.CallStateRinging,
	}
	c := callUIFromSession("acct", cs, "Bob", false)
	if !c.incoming || c.state != string(cores.CallStateRinging) {
		t.Fatalf("incoming=%v state=%q", c.incoming, c.state)
	}
	if c.callID != "call2" || c.chatID != "8" || c.peerName != "Bob" {
		t.Fatalf("fields: %+v", c)
	}
	// No resolved peer name → honest fallback, never a blank line.
	c2 := callUIFromSession("acct", cs, "", false)
	if c2.peerName != "Unknown caller" {
		t.Fatalf("peerName fallback = %q", c2.peerName)
	}
}

func TestCallUIMatches(t *testing.T) {
	c := newOutgoingCall("a1", "7", "A", false, "c1")
	if !c.matches("a1", "c1") {
		t.Fatal("same account+call must match")
	}
	if c.matches("a2", "c1") || c.matches("a1", "c2") {
		t.Fatal("different account or call must not match")
	}
}

func TestCallUIApplyEvent(t *testing.T) {
	now := time.Unix(1000000, 0)
	c := newOutgoingCall("a1", "7", "A", false, "c1")

	// ringing → connecting → active: startedAt stamped once.
	if !c.applyEvent(string(cores.CallStateConnecting), now) {
		t.Fatal("connecting must change state")
	}
	if c.state != string(cores.CallStateConnecting) {
		t.Fatalf("state = %q", c.state)
	}
	if !c.applyEvent(string(cores.CallStateActive), now.Add(2*time.Second)) {
		t.Fatal("active must change state")
	}
	if !c.startedAt.Equal(now.Add(2 * time.Second)) {
		t.Fatalf("startedAt = %v", c.startedAt)
	}
	// Stale ringing after active must be ignored (no timer reset).
	if c.applyEvent(string(cores.CallStateRinging), now.Add(3*time.Second)) {
		t.Fatal("stale ringing after active must be ignored")
	}
	if c.state != string(cores.CallStateActive) {
		t.Fatalf("state after stale ringing = %q", c.state)
	}
	// ended is terminal.
	if !c.applyEvent(string(cores.CallStateEnded), now.Add(60*time.Second)) {
		t.Fatal("ended must change state")
	}
	if !c.endedAt.Equal(now.Add(60 * time.Second)) {
		t.Fatalf("endedAt = %v", c.endedAt)
	}
	if c.applyEvent(string(cores.CallStateActive), now.Add(70*time.Second)) {
		t.Fatal("events after ended must be ignored")
	}
}

func TestCallUIStatusLine(t *testing.T) {
	now := time.Unix(1000000, 0)
	c := newOutgoingCall("a1", "7", "A", false, "c1")
	if s := c.statusLine(now); s != "Ringing…" {
		t.Fatalf("outgoing ringing = %q", s)
	}
	in := callUIFromSession("a1", &cores.CallSession{ID: "c2", State: cores.CallStateRinging}, "B", false)
	if s := in.statusLine(now); s != "Incoming call…" {
		t.Fatalf("incoming ringing = %q", s)
	}
	c.applyEvent(string(cores.CallStateConnecting), now)
	if s := c.statusLine(now); s != "Connecting…" {
		t.Fatalf("connecting = %q", s)
	}
	c.applyEvent(string(cores.CallStateActive), now.Add(5*time.Second))
	if s := c.statusLine(now.Add(5 * time.Second)); s != "0:00" {
		t.Fatalf("active at start = %q, want 0:00", s)
	}
	if s := c.statusLine(now.Add(5*time.Second + 65*time.Second)); s != "1:05" {
		t.Fatalf("elapsed = %q, want 1:05", s)
	}
	c.applyEvent(string(cores.CallStateEnded), now.Add(5*time.Second+125*time.Second))
	if s := c.statusLine(now.Add(999 * time.Second)); s != "Call ended · 2:05" {
		t.Fatalf("ended = %q, want 'Call ended · 2:05'", s)
	}
	// Ended without ever being active: no duration to show.
	c2 := newOutgoingCall("a1", "7", "A", false, "c3")
	c2.applyEvent(string(cores.CallStateEnded), now)
	if s := c2.statusLine(now); s != "Call ended" {
		t.Fatalf("never-active ended = %q", s)
	}
}

func TestCallUIControls(t *testing.T) {
	now := time.Unix(1000000, 0)
	// Incoming ringing: accept + decline.
	in := callUIFromSession("a1", &cores.CallSession{ID: "c1", State: cores.CallStateRinging}, "B", false)
	ct := in.controls()
	if !ct.accept || !ct.decline || ct.mute || ct.camera || ct.end || ct.close {
		t.Fatalf("incoming ringing controls: %+v", ct)
	}
	// Outgoing ringing: only end (cancel).
	out := newOutgoingCall("a1", "7", "A", false, "c2")
	ct = out.controls()
	if ct.accept || ct.decline || ct.mute || ct.camera || !ct.end || ct.close {
		t.Fatalf("outgoing ringing controls: %+v", ct)
	}
	// Active voice call: mute + end, no camera.
	out.applyEvent(string(cores.CallStateActive), now)
	ct = out.controls()
	if ct.accept || ct.decline || !ct.mute || ct.camera || !ct.end || ct.close {
		t.Fatalf("active voice controls: %+v", ct)
	}
	// Active video call: camera control appears.
	vid := newOutgoingCall("a1", "7", "A", true, "c3")
	vid.applyEvent(string(cores.CallStateActive), now)
	ct = vid.controls()
	if !ct.mute || !ct.camera || !ct.end || ct.accept || ct.decline || ct.close {
		t.Fatalf("active video controls: %+v", ct)
	}
	// Ended: only close.
	out.applyEvent(string(cores.CallStateEnded), now)
	ct = out.controls()
	if !ct.close || ct.accept || ct.decline || ct.mute || ct.camera || ct.end {
		t.Fatalf("ended controls: %+v", ct)
	}
}

func TestCallUIDismissible(t *testing.T) {
	now := time.Unix(1000000, 0)
	c := newOutgoingCall("a1", "7", "A", false, "c1")
	if c.dismissible(now) {
		t.Fatal("non-ended call is never dismissible")
	}
	c.applyEvent(string(cores.CallStateEnded), now)
	if c.dismissible(now.Add(3 * time.Second)) {
		t.Fatal("ended <4s must stay up")
	}
	if !c.dismissible(now.Add(5 * time.Second)) {
		t.Fatal("ended ≥4s must be dismissible")
	}
}

func TestCallElapsedTicker(t *testing.T) {
	// The 1s invalidation loop must run while the call is active for the
	// same session only.
	c := newOutgoingCall("a1", "7", "A", false, "c1")
	if callElapsedTickerWanted(c, "a1", "c1") {
		t.Fatal("non-active call must not tick")
	}
	c.applyEvent(string(cores.CallStateActive), time.Now())
	if !callElapsedTickerWanted(c, "a1", "c1") {
		t.Fatal("active call must tick")
	}
	if callElapsedTickerWanted(c, "a2", "c1") || callElapsedTickerWanted(c, "a1", "c9") {
		t.Fatal("different session must not tick")
	}
	c.applyEvent(string(cores.CallStateEnded), time.Now())
	if callElapsedTickerWanted(c, "a1", "c1") {
		t.Fatal("ended call must not tick")
	}
}
