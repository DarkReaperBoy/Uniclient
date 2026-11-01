package gui

import (
	"testing"
	"time"

	"uniclient/cores"
)

func TestCallRateGating(t *testing.T) {
	c := &callUI{state: string(cores.CallStateActive), startedAt: time.Now().Add(-4 * time.Second)}
	if callRateable(c, time.Now()) {
		t.Fatal("4s call must not be rateable")
	}
	c2 := &callUI{state: string(cores.CallStateEnded)}
	if callRateable(c2, time.Now()) {
		t.Fatal("never-active call must not be rateable")
	}
	c3 := &callUI{
		state:     string(cores.CallStateEnded),
		startedAt: time.Now().Add(-2 * time.Minute),
		endedAt:   time.Now(),
	}
	if !callRateable(c3, time.Now()) {
		t.Fatal("2-minute ended call must be rateable")
	}
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
	st.setStars(3)
	if st.stars != 3 {
		t.Fatalf("second tap on same star changed it to %d", st.stars)
	}
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
	if !st.canSend() {
		t.Fatal("4 stars must be sendable")
	}
	st.stars = 0
	if st.canSend() {
		t.Fatal("0 stars must not be sendable")
	}
}
