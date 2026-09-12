package gui

// suggestionbar_test.go — slice 171: the chat-list top-bar suggestion
// card (tdesktop dialogs/suggestions 1:1). Primary sources read via the
// GitHub API (AyuGramDesktop dev): suggestion.cpp AllSpecs() defines the
// priority order BIRTHDAY_CONTACTS_TODAY > BIRTHDAY_SETUP >
// CUSTOM_PROMO > GIFT_AUCTIONS > LOW_CREDITS_SUBS > PREMIUM_GRACE >
// PREMIUM_OFFER > UNREVIEWED_AUTH > USERPIC_SETUP; promo_suggestions.cpp
// maps help.getPromoData pending_suggestions + custom_pending_suggestion
// and dismisses via help.dismissSuggestion. Keys without a real local
// action are hidden exactly like tdesktop hides unknown keys.

import "testing"

func suggState(keys []string, custom bool, birthdays int, own *selfState) suggestionState {
	st := suggestionState{Pending: keys, dismissed: map[string]bool{}}
	if custom {
		c := promoSuggestionInfo{Key: "custom", Title: "Server card", Description: "From the server", URL: "https://example.org"}
		st.Custom = &c
	}
	if birthdays > 0 {
		st.BirthdayContacts = make([]birthdayContactInfo, birthdays)
		for i := range st.BirthdayContacts {
			st.BirthdayContacts[i] = birthdayContactInfo{UserID: int64(i + 1), Name: "u"}
		}
	}
	if own != nil {
		st.Self = *own
	}
	return st
}

func TestSuggestionPickOrder(t *testing.T) {
	all := []string{
		"BIRTHDAY_CONTACTS_TODAY", "BIRTHDAY_SETUP", "GIFT_AUCTIONS",
		"LOW_CREDITS_SUBS", "PREMIUM_GRACE", "PREMIUM_OFFER",
		"UNREVIEWED_AUTH", "USERPIC_SETUP",
	}
	// tdesktop AllSpecs order, skipping the keys we cannot act on for
	// real (gift auctions / low credits / grace / unreviewed auth — no
	// local surface yet, honest absence).
	want := []string{"BIRTHDAY_CONTACTS_TODAY", "BIRTHDAY_SETUP", "PREMIUM_OFFER", "USERPIC_SETUP"}
	own := &selfState{BirthdaySet: true}
	got := pickSuggestion(suggState(all, false, 3, own))
	if got == nil || got.Key != want[0] {
		t.Fatalf("pick = %v, want %s", got, want[0])
	}
	// Birthday contacts visible even without the server key (tdesktop's
	// current() returns true while the birthday set is unknown; ours is
	// local and definitive — non-empty birthdays show).
	got = pickSuggestion(suggState(nil, false, 2, own))
	if got == nil || got.Key != "BIRTHDAY_CONTACTS_TODAY" {
		t.Fatalf("birthday-only pick = %v", got)
	}
	// Walk the ladder: each level appears after the previous is gone.
	// (BIRTHDAY_CONTACTS_TODAY needs local birthday contacts — the
	// server key alone never fabricates the card; its precedence is
	// pinned by the assertions above.)
	ladder := []string{"BIRTHDAY_SETUP", "custom", "PREMIUM_OFFER", "USERPIC_SETUP"}
	st := suggState(all, true, 0, own)
	for _, wantKey := range ladder {
		got := pickSuggestion(st)
		if got == nil || got.Key != wantKey {
			t.Fatalf("ladder pick = %v, want %s", got, wantKey)
		}
		st.dismissed[wantKey] = true
	}
	// Custom promo card sits between BIRTHDAY_SETUP and PREMIUM_OFFER.
	st = suggState(all, true, 0, own)
	st.dismissed["BIRTHDAY_SETUP"] = true
	got = pickSuggestion(st)
	if got == nil || got.Key != "custom" {
		t.Fatalf("custom pick = %v", got)
	}
	// Nothing pending, nothing local → no bar at all.
	if got := pickSuggestion(suggState(nil, false, 0, own)); got != nil {
		t.Fatalf("empty pick = %v, want nil", got)
	}
}

func TestSuggestionBirthdaySetupGates(t *testing.T) {
	// BIRTHDAY_SETUP hides on the owner's own birthday today (tdesktop:
	// !Data::IsBirthdayToday(session->user()->birthday())).
	today := &selfState{BirthdaySet: true, BirthdayIsToday: true}
	if got := pickSuggestion(suggState([]string{"BIRTHDAY_SETUP"}, false, 0, today)); got != nil {
		t.Fatalf("birthday-setup on own birthday = %v, want nil", got)
	}
	other := &selfState{BirthdaySet: true, BirthdayIsToday: false}
	if got := pickSuggestion(suggState([]string{"BIRTHDAY_SETUP"}, false, 0, other)); got == nil || got.Key != "BIRTHDAY_SETUP" {
		t.Fatalf("birthday-setup pick = %v", got)
	}
}

func TestSuggestionUnknownKeysHidden(t *testing.T) {
	// Keys with no real local action never render (tdesktop hides
	// unknown keys the same way).
	own := &selfState{BirthdaySet: true}
	for _, key := range []string{"GIFT_AUCTIONS", "LOW_CREDITS_SUBS", "PREMIUM_GRACE", "UNREVIEWED_AUTH", "SOME_FUTURE_KEY"} {
		if got := pickSuggestion(suggState([]string{key}, false, 0, own)); got != nil {
			t.Fatalf("pick(%s) = %v, want nil", key, got)
		}
	}
}

func TestSuggestionDismiss(t *testing.T) {
	st := suggState([]string{"BIRTHDAY_SETUP"}, false, 0, &selfState{BirthdaySet: true})
	p := pickSuggestion(st)
	if p == nil {
		t.Fatal("no pick before dismiss")
	}
	st.dismiss("BIRTHDAY_SETUP")
	if got := pickSuggestion(st); got != nil {
		t.Fatalf("pick after dismiss = %v, want nil", got)
	}
	// Server-pending keys stay hidden after local dismiss even on a
	// refetch that still lists them (help.dismissSuggestion is async).
	st2 := suggState([]string{"BIRTHDAY_SETUP"}, false, 0, &selfState{BirthdaySet: true})
	st2.dismissed["BIRTHDAY_SETUP"] = true
	if got := pickSuggestion(st2); got != nil {
		t.Fatalf("pick with stale server key = %v, want nil", got)
	}
}

func TestSuggestionTitles(t *testing.T) {
	cases := []struct {
		key, wantTitle string
	}{
		{"BIRTHDAY_CONTACTS_TODAY", "u has a birthday today"},
		{"PREMIUM_OFFER", "Upgrade to Premium"},
		{"USERPIC_SETUP", "Add a profile photo"},
		{"BIRTHDAY_SETUP", "Add your birthday"},
	}
	for _, c := range cases {
		n := 0
		if c.key == "BIRTHDAY_CONTACTS_TODAY" {
			n = 1
		}
		st := suggState([]string{c.key}, false, n, &selfState{BirthdaySet: true})
		got := pickSuggestion(st)
		if got == nil {
			t.Fatalf("pick(%s) = nil", c.key)
		}
		if got.Title != c.wantTitle {
			t.Errorf("title(%s) = %q, want %q", c.key, got.Title, c.wantTitle)
		}
	}
}
