package engine

import (
	"errors"
	"testing"

	"uniclient/cores"
)

var errFavBoom = errors.New("fav boom")

// Slice 172 — favorite-reaction session cache: the corner reaction pill
// reads the favorite in the layout path, so the engine must serve it from
// a per-session cache (one core RPC per account) instead of re-fetching
// help.getConfig on every read; a server-side empty result caches too (the
// GUI 👍 fallback then sticks without RPC churn), errors do not cache.

type favReactStub struct {
	cores.StubCore
	fav     string
	err     error
	calls   int
	setTo   string
	setCall int
}

func (s *favReactStub) GetDefaultReaction() (string, error) {
	s.calls++
	if s.err != nil {
		return "", s.err
	}
	return s.fav, nil
}

func (s *favReactStub) SetDefaultReaction(emoji string) error {
	s.setCall++
	s.setTo = emoji
	return nil
}

func TestGetDefaultReactionSessionCache(t *testing.T) {
	e := newTestEngine(t)
	st := &favReactStub{fav: "🔥"}
	e.accounts = map[string]*Account{"a1": {ID: "a1", Core: st}}
	for i := 0; i < 5; i++ {
		got, err := e.GetDefaultReaction("a1")
		if err != nil || got != "🔥" {
			t.Fatalf("get #%d = (%q,%v), want (🔥,nil)", i, got, err)
		}
	}
	if st.calls != 1 {
		t.Fatalf("core hit %d times, want exactly 1 (session cache)", st.calls)
	}
}

func TestGetDefaultReactionCustomKeyPassthrough(t *testing.T) {
	e := newTestEngine(t)
	st := &favReactStub{fav: "custom_7"}
	e.accounts = map[string]*Account{"a1": {ID: "a1", Core: st}}
	got, err := e.GetDefaultReaction("a1")
	if err != nil || got != "custom_7" {
		t.Fatalf("custom favorite = (%q,%v), want (custom_7,nil)", got, err)
	}
}

func TestGetDefaultReactionEmptyCaches(t *testing.T) {
	e := newTestEngine(t)
	st := &favReactStub{fav: ""}
	e.accounts = map[string]*Account{"a1": {ID: "a1", Core: st}}
	for i := 0; i < 3; i++ {
		if got, err := e.GetDefaultReaction("a1"); err != nil || got != "" {
			t.Fatalf("empty favorite get #%d = (%q,%v)", i, got, err)
		}
	}
	if st.calls != 1 {
		t.Fatalf("empty result must cache (no per-frame RPC storm), core hit %d times", st.calls)
	}
}

func TestGetDefaultReactionErrorDoesNotCache(t *testing.T) {
	e := newTestEngine(t)
	st := &favReactStub{err: errFavBoom}
	e.accounts = map[string]*Account{"a1": {ID: "a1", Core: st}}
	if _, err := e.GetDefaultReaction("a1"); err == nil {
		t.Fatal("core error should propagate")
	}
	// Recovery: a later call must retry (errors are transient).
	st.err, st.fav = nil, "🎉"
	if got, err := e.GetDefaultReaction("a1"); err != nil || got != "🎉" {
		t.Fatalf("recovered get = (%q,%v), want (🎉,nil)", got, err)
	}
	if st.calls != 2 {
		t.Fatalf("core hit %d times, want 2 (error not cached)", st.calls)
	}
}

func TestSetDefaultReactionWritesCache(t *testing.T) {
	e := newTestEngine(t)
	st := &favReactStub{}
	e.accounts = map[string]*Account{"a1": {ID: "a1", Core: st}}
	if err := e.SetDefaultReaction("a1", "custom_9"); err != nil {
		t.Fatal(err)
	}
	if st.setTo != "custom_9" || st.setCall != 1 {
		t.Fatalf("core set = (%q,%d), want (custom_9,1)", st.setTo, st.setCall)
	}
	// Write-through: the next read must not re-fetch.
	if got, err := e.GetDefaultReaction("a1"); err != nil || got != "custom_9" {
		t.Fatalf("post-set get = (%q,%v), want (custom_9,nil)", got, err)
	}
	if st.calls != 0 {
		t.Fatalf("post-set get re-fetched the core %d times, want 0 (write-through cache)", st.calls)
	}
}
