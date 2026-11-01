package gui

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
	cur := []cores.Reaction{
		{Emoji: "👍", Count: 4, ByMe: true},
		{Emoji: "🔥", Count: 1, ByMe: true},
		{Emoji: "🎉", Count: 2, ByMe: false},
	}

	got := toggleOwnReactionEmojis(cur, "👍")
	if len(got) != 1 || got[0] != "🔥" {
		t.Errorf("remove favorite: %v", got)
	}

	got = toggleOwnReactionEmojis(cur, "❤️")
	if len(got) != 3 || got[0] != "👍" || got[1] != "🔥" || got[2] != "❤️" {
		t.Errorf("add favorite: %v", got)
	}

	got = toggleOwnReactionEmojis([]cores.Reaction{{Emoji: "🎉", Count: 2}}, "❤️")
	if len(got) != 1 || got[0] != "❤️" {
		t.Errorf("fresh add: %v", got)
	}

	got = toggleOwnReactionEmojis([]cores.Reaction{{Emoji: "👍", Count: 1, ByMe: true}}, "👍")
	if len(got) != 0 {
		t.Errorf("sole favorite removal: %v", got)
	}

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
	if fav := favoriteReactionOrDefault(""); fav != "👍" {
		t.Errorf("empty favorite = %q, want 👍", fav)
	}
	if fav := favoriteReactionOrDefault("❤️"); fav != "❤️" {
		t.Errorf("stored favorite passthrough: %q", fav)
	}
}

func TestCustomKeyDocID(t *testing.T) {
	if d, ok := customKeyDocID("custom_42"); !ok || d != 42 {
		t.Errorf("custom_42 = (%d,%v), want (42,true)", d, ok)
	}
	if _, ok := customKeyDocID("👍"); ok {
		t.Error("plain emoji is not a custom key")
	}
	if _, ok := customKeyDocID("custom_bogus"); ok {
		t.Error("malformed custom key is not a custom key")
	}
}

func TestOwnHasReactionCustom(t *testing.T) {
	reacts := []cores.Reaction{
		{Emoji: "", DocumentID: 42, Count: 1, ByMe: true},
		{Emoji: "🔥", Count: 3, ByMe: true},
	}
	if !ownHasReaction(reacts, "custom_42") {
		t.Error("own custom_42 reaction should match favorite custom_42")
	}
	if ownHasReaction(reacts, "custom_7") {
		t.Error("unrelated custom key must not match")
	}
	if !ownHasReaction(reacts, "🔥") {
		t.Error("emoji matching must keep working")
	}
}

func TestToggleOwnReactionEmojisCustom(t *testing.T) {
	cur := []cores.Reaction{
		{Emoji: "", DocumentID: 42, Count: 1, ByMe: true},
		{Emoji: "🔥", Count: 1, ByMe: true},
		{Emoji: "🎉", Count: 2, ByMe: false},
	}
	got := toggleOwnReactionEmojis(cur, "custom_42")
	if len(got) != 1 || got[0] != "🔥" {
		t.Fatalf("custom toggle-off = %v, want [🔥]", got)
	}
	got = toggleOwnReactionEmojis(cur, "custom_7")
	if len(got) != 3 || got[0] != "custom_42" || got[1] != "🔥" || got[2] != "custom_7" {
		t.Fatalf("custom toggle-on = %v, want [custom_42 🔥 custom_7]", got)
	}
}
