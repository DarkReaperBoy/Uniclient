package gui

// Corner reaction button (slice 159, tdesktop cornerReaction 1:1): the
// NE-corner pill on hovered bubbles that toggles the account's default
// (favorite) reaction — tdesktop Data::Reactions::favoriteId +
// toggleFavoriteReaction semantics. Pure logic locked here.

import (
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

func TestEffectiveCornerReaction(t *testing.T) {
	on, off := true, false
	if !effectiveCornerReaction(nil) {
		t.Error("nil config must default ON (tdesktop _cornerReaction = true)")
	}
	if !effectiveCornerReaction(&on) {
		t.Error("explicit on")
	}
	if effectiveCornerReaction(&off) {
		t.Error("explicit off")
	}
}

func TestCornerReactGate(t *testing.T) {
	msg := engine.CachedMessage{MsgID: "55"}
	cases := []struct {
		name            string
		cornerOn, selOn bool
		m               engine.CachedMessage
		want            bool
	}{
		{"plain incoming", true, false, msg, true},
		{"own message reacts too", true, false, engine.CachedMessage{MsgID: "55", IsOutgoing: true}, true},
		{"setting off", false, false, msg, false},
		{"selection mode", true, true, msg, false},
		{"service msg", true, false, engine.CachedMessage{MsgID: "55", IsService: true}, false},
		{"no id", true, false, engine.CachedMessage{}, false},
	}
	for _, c := range cases {
		if got := cornerReactGate(c.cornerOn, c.selOn, c.m); got != c.want {
			t.Errorf("%s: cornerReactGate = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestToggleOwnReactionEmojis(t *testing.T) {
	// Own reactions: 👍 (fav) + 🔥; others' 👍x3.
	cur := []cores.Reaction{
		{Emoji: "👍", Count: 4, ByMe: true},
		{Emoji: "🔥", Count: 1, ByMe: true},
		{Emoji: "🎉", Count: 2, ByMe: false},
	}

	// Favorite present → removed from the own list, others kept.
	got := toggleOwnReactionEmojis(cur, "👍")
	if len(got) != 1 || got[0] != "🔥" {
		t.Errorf("remove favorite: %v", got)
	}

	// Favorite absent → appended after existing own reactions.
	got = toggleOwnReactionEmojis(cur, "❤️")
	if len(got) != 3 || got[0] != "👍" || got[1] != "🔥" || got[2] != "❤️" {
		t.Errorf("add favorite: %v", got)
	}

	// No own reactions at all → the favorite alone.
	got = toggleOwnReactionEmojis([]cores.Reaction{{Emoji: "🎉", Count: 2}}, "❤️")
	if len(got) != 1 || got[0] != "❤️" {
		t.Errorf("fresh add: %v", got)
	}

	// Only the favorite is own → removal yields the empty list (server
	// semantics: empty reaction vector removes all own reactions).
	got = toggleOwnReactionEmojis([]cores.Reaction{{Emoji: "👍", Count: 1, ByMe: true}}, "👍")
	if len(got) != 0 {
		t.Errorf("sole favorite removal: %v", got)
	}

	// No reactions at all → the favorite alone.
	got = toggleOwnReactionEmojis(nil, "🔥")
	if len(got) != 1 || got[0] != "🔥" {
		t.Errorf("nil list: %v", got)
	}
}

func TestOwnHasReaction(t *testing.T) {
	cur := []cores.Reaction{
		{Emoji: "👍", Count: 4, ByMe: true},
		{Emoji: "🎉", Count: 2, ByMe: false},
	}
	if !ownHasReaction(cur, "👍") {
		t.Error("own 👍 must register")
	}
	if ownHasReaction(cur, "🎉") {
		t.Error("someone else's 🎉 is not own")
	}
	if ownHasReaction(nil, "👍") {
		t.Error("nil list has nothing")
	}
}

func TestFavoriteReactionFallback(t *testing.T) {
	// Empty stored favorite falls back to tdesktop's default 👍.
	if fav := favoriteReactionOrDefault(""); fav != "👍" {
		t.Errorf("empty favorite = %q, want 👍", fav)
	}
	if fav := favoriteReactionOrDefault("❤️"); fav != "❤️" {
		t.Errorf("stored favorite passthrough: %q", fav)
	}
}
