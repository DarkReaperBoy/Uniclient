package gui

import (
	"testing"
	"time"
)

// Login-code relay (AyuGram parity slice 31).

func TestLoginCodeFresh(t *testing.T) {
	now := time.Now()
	if loginCodeFresh("", now, now) {
		t.Error("empty code is fresh")
	}
	if loginCodeFresh("12345", time.Time{}, now) {
		t.Error("zero time is fresh")
	}
	if !loginCodeFresh("12345", now.Add(-2*time.Minute), now) {
		t.Error("2-minute-old code should be fresh")
	}
	if loginCodeFresh("12345", now.Add(-11*time.Minute), now) {
		t.Error("11-minute-old code should be stale")
	}
}

func TestLoginCodeBannerText(t *testing.T) {
	if got := loginCodeBannerText("54321"); got != "Code from your other account: 54321" {
		t.Errorf("banner text = %q", got)
	}
}
