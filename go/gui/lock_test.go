package gui

// Local passcode lock (slice 87): hash derivation, vault mapping, the
// attempt state machine (unlock / wrong / cooldown), autolock decisions,
// and the settings dialog's step machine.

import (
	"testing"
	"time"
)

func TestPinHashOf(t *testing.T) {
	a := pinHashOf("s1", "1234")
	b := pinHashOf("s1", "1234")
	c := pinHashOf("s2", "1234")
	d := pinHashOf("s1", "4321")
	if a != b {
		t.Error("hash must be deterministic")
	}
	if a == c || a == d {
		t.Error("salt or pin changes must change the hash")
	}
	if len(a) != 64 {
		t.Errorf("hash len = %d, want 64 hex chars", len(a))
	}
}

func TestLockFromConfig(t *testing.T) {
	if st := lockFromConfig(nil); st != nil {
		t.Error("nil config → nil state")
	}
	if st := lockFromConfig(map[string]interface{}{"enabled": false}); st != nil {
		t.Error("disabled → nil state")
	}
	if st := lockFromConfig(map[string]interface{}{"enabled": true, "salt": "", "hash": "x"}); st != nil {
		t.Error("missing salt/hash → nil state (incomplete record)")
	}
	st := lockFromConfig(map[string]interface{}{
		"enabled": true, "digits": 5.0, "autolock": 5.0,
		"salt": "aabb", "hash": "ccdd",
	})
	if st == nil {
		t.Fatal("enabled record → state")
	}
	if !st.locked {
		t.Error("boot state must be locked")
	}
	if st.digits != 5 || st.autolockMin != 5 || st.salt != "aabb" || st.hash != "ccdd" {
		t.Errorf("fields = %+v", st)
	}
	// Clamp ranges and defaults.
	st = lockFromConfig(map[string]interface{}{
		"enabled": true, "digits": 99.0, "autolock": -3.0, "salt": "s", "hash": "h",
	})
	if st.digits != 6 || st.autolockMin != 0 {
		t.Errorf("clamp: digits=%d autolock=%d, want 6/0", st.digits, st.autolockMin)
	}
	st = lockFromConfig(map[string]interface{}{"enabled": true, "salt": "s", "hash": "h"})
	if st.digits != 4 {
		t.Errorf("default digits = %d, want 4", st.digits)
	}
}

func TestLockToConfigRoundtrip(t *testing.T) {
	st := &lockState{digits: 6, autolockMin: 5, salt: "s", hash: "h", locked: true}
	cfg := st.toConfig()
	back := lockFromConfig(cfg)
	if back == nil || back.digits != 6 || back.autolockMin != 5 || back.salt != "s" || back.hash != "h" {
		t.Errorf("roundtrip lost fields: %+v", back)
	}
}

func lockForPin(pin string) *lockState {
	st := &lockState{digits: 4, salt: "s"}
	st.hash = pinHashOf(st.salt, pin)
	return st
}

func TestLockFeedAndUnlock(t *testing.T) {
	now := time.Now()
	st := lockForPin("1357")
	st.locked = true

	// Digits accumulate; non-digits and overflow are ignored.
	if !lockFeedDigit(st, '1') || st.input != "1" {
		t.Fatalf("first digit: %q", st.input)
	}
	if lockFeedDigit(st, 'x') {
		t.Error("non-digit must be ignored")
	}
	lockFeedDigit(st, '3')
	lockFeedDigit(st, '5')
	lockBackspace(st)
	if st.input != "13" {
		t.Fatalf("backspace: %q", st.input)
	}
	lockFeedDigit(st, '5')
	lockFeedDigit(st, '7')
	if st.input != "1357" {
		t.Fatalf("full input: %q", st.input)
	}
	if lockFeedDigit(st, '9') {
		t.Error("input beyond digits must be ignored")
	}

	// Correct PIN unlocks.
	if !lockTryAttempt(st, now) {
		t.Fatal("correct pin must unlock")
	}
	if st.locked || st.wrong || st.input != "" {
		t.Errorf("post-unlock state: %+v", st)
	}

	// Wrong PIN: bookkeeping, then cooldown after maxLockWrong.
	st.locked = true
	for i := 1; i <= maxLockWrong-1; i++ {
		for _, d := range "9999" {
			lockFeedDigit(st, byte(d))
		}
		if lockTryAttempt(st, now) {
			t.Fatal("wrong pin must not unlock")
		}
		if !st.wrong || st.wrongCount != i {
			t.Fatalf("wrong bookkeeping @%d: %+v", i, st)
		}
	}
	for _, d := range "9999" {
		lockFeedDigit(st, byte(d))
	}
	if lockTryAttempt(st, now) {
		t.Fatal("wrong pin must not unlock")
	}
	if !lockFrozen(st, now) {
		t.Error("5th wrong attempt must freeze the pad")
	}
	// Frozen pads reject input entirely.
	if lockFeedDigit(st, '1') {
		t.Error("frozen pad must ignore digits")
	}
	// Cooldown expires.
	if lockFrozen(st, now.Add(lockFreezeSecond+time.Second)) {
		t.Error("freeze must expire")
	}
}

func TestLockShouldAutolock(t *testing.T) {
	now := time.Now()
	if lockShouldAutolock(nil, now) {
		t.Error("nil lock never autolocks")
	}
	st := &lockState{autolockMin: 5, locked: false, lastActive: now}
	if lockShouldAutolock(st, now.Add(2*time.Minute)) {
		t.Error("2 min < 5 min: no autolock")
	}
	if !lockShouldAutolock(st, now.Add(6*time.Minute)) {
		t.Error("6 min > 5 min: autolock")
	}
	st.locked = true
	if lockShouldAutolock(st, now.Add(99*time.Minute)) {
		t.Error("already locked: no autolock decision")
	}
	st2 := &lockState{autolockMin: 0, lastActive: now}
	if lockShouldAutolock(st2, now.Add(100*time.Hour)) {
		t.Error("autolock 0 = never")
	}
	st3 := &lockState{autolockMin: 1} // never active
	if lockShouldAutolock(st3, now) {
		t.Error("no activity recorded: no autolock (avoid instant lock)")
	}
}

func TestLockKeyHelpers(t *testing.T) {
	if lockKeyOf("⌫") != "back" || lockKeyOf("7") != "7" {
		t.Error("key mapping")
	}
	if lockPadIndex("⌫") != 10 || lockPadIndex("0") != 0 || lockPadIndex("9") != 9 {
		t.Error("pad index mapping")
	}
	if lockPadIndex("") != -1 || lockPadIndex("x") != -1 {
		t.Error("invalid keys map to -1")
	}
	st := lockForPin("1111")
	if !lockFeedKey(st, "1") || st.input != "1" {
		t.Error("feed key digit")
	}
	if !lockFeedKey(st, "back") || st.input != "" {
		t.Error("feed key back")
	}
}

func TestLockClampDigits(t *testing.T) {
	for n, want := range map[int]int{1: 4, 3: 4, 4: 4, 5: 5, 6: 6, 7: 6, 9: 6} {
		if got := lockClampDigits(n); got != want {
			t.Errorf("clamp(%d) = %d, want %d", n, got, want)
		}
	}
}

func TestLockDlgCaption(t *testing.T) {
	now := time.Now()
	d := &lockDlgState{step: lockDlgVerify}
	if c, err := lockDlgCaption(d, now); c != "Enter current passcode" || err {
		t.Errorf("verify caption: %q %v", c, err)
	}
	d.wrong = true
	if c, err := lockDlgCaption(d, now); c != "Wrong passcode" || !err {
		t.Errorf("wrong caption: %q %v", c, err)
	}
	d.frozen = now.Add(10 * time.Second)
	if _, err := lockDlgCaption(d, now); !err {
		t.Error("frozen caption must be an error caption")
	}
	d2 := &lockDlgState{step: lockDlgNew, digits: 5}
	if c, _ := lockDlgCaption(d2, now); c != "Enter new passcode (5 digits)" {
		t.Errorf("new caption: %q", c)
	}
}

func TestLockDlgFeedSteps(t *testing.T) {
	now := time.Now()
	cur := lockForPin("2468")

	// Fresh install: new → confirm → saved.
	d := &lockDlgState{step: lockDlgNew, digits: 4}
	for _, k := range []string{"1", "2", "3", "4"} {
		if act := lockDlgFeed(d, cur, k, now); act != "" {
			t.Fatalf("new step leaked action %q", act)
		}
	}
	if d.step != lockDlgConfirm || d.first != "1234" {
		t.Fatalf("after new: step=%d first=%q", d.step, d.first)
	}
	// Mismatching confirm restarts from entry.
	for _, k := range []string{"4", "3", "2", "1"} {
		if act := lockDlgFeed(d, cur, k, now); act != "" {
			t.Fatalf("confirm mismatch leaked action %q", act)
		}
	}
	if d.step != lockDlgNew || !d.wrong {
		t.Fatalf("mismatch must restart: step=%d wrong=%v", d.step, d.wrong)
	}
	// Matching confirm saves: entry step feeds return "", the confirm
	// step's completing feed returns the save action.
	d2 := &lockDlgState{step: lockDlgNew, digits: 4}
	for _, k := range []string{"9", "8", "7", "6"} {
		if act := lockDlgFeed(d2, cur, k, now); act != "" {
			t.Fatalf("entry feed leaked %q", act)
		}
	}
	if d2.step != lockDlgConfirm || d2.first != "9876" {
		t.Fatalf("entry complete: step=%d first=%q", d2.step, d2.first)
	}
	for _, k := range []string{"9", "8", "7"} {
		if act := lockDlgFeed(d2, cur, k, now); act != "" {
			t.Fatalf("confirm feed leaked %q", act)
		}
	}
	if act := lockDlgFeed(d2, cur, "6", now); act != "saved:9876" {
		t.Fatalf("confirm action = %q, want saved:9876", act)
	}

	// Verify step: correct current PIN → verified; wrong → error state.
	d3 := &lockDlgState{step: lockDlgVerify}
	for _, k := range []string{"2", "4", "6"} {
		lockDlgFeed(d3, cur, k, now)
	}
	if act := lockDlgFeed(d3, cur, "8", now); act != "verified" {
		t.Fatalf("verify action = %q, want verified", act)
	}
	d4 := &lockDlgState{step: lockDlgVerify}
	for _, k := range []string{"0", "0", "0", "0"} {
		lockDlgFeed(d4, cur, k, now)
	}
	if !d4.wrong || d4.input != "" {
		t.Errorf("wrong verify: wrong=%v input=%q", d4.wrong, d4.input)
	}

	// Frozen dialog rejects input.
	d5 := &lockDlgState{step: lockDlgNew, digits: 4, frozen: now.Add(time.Hour)}
	if lockDlgFeed(d5, cur, "1", now) != "" || d5.input != "" {
		t.Error("frozen dialog must ignore keys")
	}
}

func TestLockDlgDigitsChanged(t *testing.T) {
	d := &lockDlgState{step: lockDlgNew, digits: 4, input: "12", first: "12"}
	lockDlgDigitsChanged(d, 6)
	if d.digits != 6 || d.input != "" || d.first != "" || d.wrong {
		t.Errorf("digits change must reset entry: %+v", d)
	}
	lockDlgDigitsChanged(d, 6) // same value: no-op, no crash
}

func TestAutolockLabel(t *testing.T) {
	for m, want := range map[int]string{0: "Never", 1: "1 min", 5: "5 min", 60: "1 h"} {
		if got := autolockLabel(m); got != want {
			t.Errorf("autolockLabel(%d) = %q, want %q", m, got, want)
		}
	}
}

func TestLockStateHasHash(t *testing.T) {
	var nilSt *lockState
	if nilSt.hasHash() {
		t.Error("nil state has no hash")
	}
	if (&lockState{}).hasHash() {
		t.Error("empty hash is incomplete")
	}
	if !(&lockState{salt: "s", hash: "h"}).hasHash() {
		t.Error("salt+hash present")
	}
}
