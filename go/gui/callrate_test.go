package gui

import (
	"testing"
	"time"

	"uniclient/cores"
)

// Call rating dialog (slice 179, parity row "Call rating dialog"):
// pure logic — after-call gating, star selection, send payload. Layout
// verified by compile + review.

func TestCallRateGating(t *testing.T) {
	// Short calls (< minRateCallDur) never rate.
	c := &callUI{state: string(cores.CallStateActive), startedAt: time.Now().Add(-4 * time.Second)}
	if callRateable(c, time.Now()) {
		t.Fatal("4s call must not be rateable")
	}
	// Missed/declined (never active) never rate.
	c2 := &callUI{state: string(cores.CallStateEnded)}
	if callRateable(c2, time.Now()) {
		t.Fatal("never-active call must not be rateable")
	}
	// A real conversation is rateable.
	c3 := &callUI{
		state:     string(cores.CallStateEnded),
		startedAt: time.Now().Add(-2 * time.Minute),
		endedAt:   time.Now(),
	}
	if !callRateable(c3, time.Now()) {
		t.Fatal("2-minute ended call must be rateable")
	}
	// Ended long after start but still measured from startedAt.
	c4 := &callUI{
		state:     string(cores.CallStateEnded),
		startedAt: time.Now().Add(-minRateCallDur - time.Second),
		endedAt:   time.Now(),
	}
	if !callRateable(c4, time.Now()) {
		t.Fatal("threshold call must be rateable")
	}
}

func TestCallRateStars(t *testing.T) {
	st := &rateCallState{}
	if st.valid() {
		t.Fatal("zero stars must be invalid")
	}
	st.setStars(3)
	if st.stars != 3 || !st.valid() {
		t.Fatalf("stars = %d valid=%v", st.stars, st.valid())
	}
	st.setStars(3) // tapping the same star again is a no-op
	if st.stars != 3 {
		t.Fatalf("second tap on same star changed it to %d", st.stars)
	}
	// Out-of-range taps are ignored.
	st2 := &rateCallState{}
	st2.setStars(6)
	if st2.stars != 0 {
		t.Fatalf("6 stars = %d", st2.stars)
	}
	st2.setStars(2)
	if st2.stars != 2 {
		t.Fatalf("2 stars = %d", st2.stars)
	}
}

func TestCallRatePayload(t *testing.T) {
	st := &rateCallState{accountID: "acc", callID: "call1", peerName: "Bob", stars: 4}
	if st.payloadComment() != "" {
		t.Fatalf("comment = %q", st.payloadComment())
	}
	// Send is enabled once stars chosen.
	if !st.canSend() {
		t.Fatal("4 stars must be sendable")
	}
	st.stars = 0
	if st.canSend() {
		t.Fatal("0 stars must not be sendable")
	}
}
